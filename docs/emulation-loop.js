// The adapter owns the emulator and returns standalone buffers ready to transfer.
const CLOCK_HZ = 4_194_304;
const MAX_CYCLES_PER_STEP = 32_768;
const MAX_CATCHUP_CYCLES = CLOCK_HZ / 4;
const FRAME_CYCLES = 70_224;
const DIRECTION_KEYS = { KeyD: 1, KeyA: 2, KeyW: 4, KeyS: 8 };
const ACTION_KEYS = { KeyK: 1, KeyJ: 2, KeyU: 4, KeyI: 8 };

export class EmulationLoop {
  constructor(adapter, emit, options = {}) {
    this.adapter = adapter;
    this.emit = emit;
    this.now = options.now || (() => performance.now());
    this.schedule = options.setTimeout || ((callback, delay) => setTimeout(callback, delay));
    this.cancel = options.clearTimeout || ((handle) => clearTimeout(handle));
    this.running = false;
    this.throttleEnabled = true;
    this.muted = true;
    this.direction = 0;
    this.action = 0;
    this.directionPending = 0;
    this.actionPending = 0;
    this.pendingCycles = 0;
    this.completedFrames = 0;
    this.loopHandle = null;
    this.loopTick = this.tick.bind(this);
    this.resetClock();
  }

  resetClock() {
    this.startTime = this.now();
    this.elapsedCycles = 0;
  }

  setThrottle(enabled) {
    this.throttleEnabled = Boolean(enabled);
    this.resetClock();
  }

  setMuted(enabled) { this.muted = Boolean(enabled); }

  setInput(directionPressed, actionPressed) {
    this.direction = directionPressed & 15;
    this.action = actionPressed & 15;
    if ((this.direction & ~this.directionPending) || (this.action & ~this.actionPending)) this.pendingCycles = 0;
    this.directionPending |= this.direction;
    this.actionPending |= this.action;
  }

  updateInput(code, pressed) {
    const directionMask = DIRECTION_KEYS[code] || 0;
    const actionMask = ACTION_KEYS[code] || 0;
    this.setInput(
      pressed ? this.direction | directionMask : this.direction & ~directionMask,
      pressed ? this.action | actionMask : this.action & ~actionMask,
    );
  }

  releaseInputs() {
    this.direction = this.action = this.directionPending = this.actionPending = 0;
    this.pendingCycles = 0;
  }

  inputMasks() {
    return [(~(this.direction | this.directionPending)) & 15, (~(this.action | this.actionPending)) & 15];
  }

  clearPending() {
    this.directionPending = this.actionPending = this.pendingCycles = 0;
  }

  sendFrame(frameCount) {
    const data = this.adapter.framebuffer();
    this.emit({ type: 'pixelData', data, frameCount, completedFrames: this.completedFrames }, [data]);
  }

  drainAudio() {
    const data = this.adapter.popAudio();
    if (!this.muted && data && data.byteLength > 0) {
      this.emit({ type: 'audioData', data }, [data]);
    }
  }

  runUnthrottledFrame() {
    const frames = this.adapter.runFrame(...this.inputMasks());
    this.completedFrames += frames;
    // Even an LCD-off fallback advances a frame's CPU time.
    this.clearPending();
    this.drainAudio();
    this.sendFrame(frames);
  }

  runThrottled() {
    const realCycles = (this.now() - this.startTime) * CLOCK_HZ / 1000;
    const targetCycles = Math.min(realCycles, this.elapsedCycles + MAX_CATCHUP_CYCLES);
    let frames = 0;
    while (targetCycles > this.elapsedCycles) {
      const remainingCycles = Math.floor(targetCycles - this.elapsedCycles);
      if (remainingCycles <= 0) break;
      const cycles = Math.min(remainingCycles, MAX_CYCLES_PER_STEP);
      const completed = this.adapter.runCycles(cycles, ...this.inputMasks());
      frames += completed;
      this.completedFrames += completed;
      // A short press survives partial-frame cycle budgets until a full frame.
      this.pendingCycles += cycles;
      if (completed > 0 || this.pendingCycles >= FRAME_CYCLES) this.clearPending();
      this.drainAudio();
      this.elapsedCycles += cycles;
    }
    if (frames > 0) this.sendFrame(frames);
  }

  start() {
    if (this.running) return;
    this.resetClock();
    this.running = true;
    this.tick();
  }

  stop() {
    this.running = false;
    if (this.loopHandle !== null) this.cancel(this.loopHandle);
    this.loopHandle = null;
    this.releaseInputs();
  }

  tick() {
    this.loopHandle = null;
    if (!this.running) return;
    try {
      if (this.throttleEnabled) this.runThrottled();
      else this.runUnthrottledFrame();
    } catch (error) {
      this.stop();
      this.emit({ type: 'error', message: error.message });
      return;
    }
    this.loopHandle = this.schedule(this.loopTick, 0);
  }
}
