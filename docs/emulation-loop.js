// The adapter owns the emulator and returns standalone buffers ready to transfer.
const CLOCK_HZ = 4_194_304;
const FRAME_CYCLES = 70_224;
const FRAME_MILLISECONDS = FRAME_CYCLES / CLOCK_HZ * 1000;

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
    this.completedFrames = 0;
    this.loopHandle = null;
    this.loopTick = this.tick.bind(this);
    this.resetClock();
  }

  resetClock() {
    this.nextFrameTime = this.now();
  }

  setThrottle(enabled) {
    this.throttleEnabled = Boolean(enabled);
    this.resetClock();
  }

  setMuted(enabled) { this.muted = Boolean(enabled); }

  setInput(directionPressed, actionPressed) {
    this.direction = directionPressed & 15;
    this.action = actionPressed & 15;
    this.directionPending |= this.direction;
    this.actionPending |= this.action;
  }

  releaseInputs() {
    this.direction = this.action = this.directionPending = this.actionPending = 0;
  }

  inputMasks() {
    return [(~(this.direction | this.directionPending)) & 15, (~(this.action | this.actionPending)) & 15];
  }

  clearPending() {
    this.directionPending = this.actionPending = 0;
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

  runFrame() {
    const frames = this.adapter.runFrame(...this.inputMasks());
    this.completedFrames += frames;
    // Even an LCD-off fallback advances a frame's CPU time.
    this.clearPending();
    this.drainAudio();
    this.sendFrame(frames);
  }

  runThrottled() {
    const now = this.now();
    if (now < this.nextFrameTime) return;
    // A delayed timer must not create a batch of invisible catch-up frames.
    if (now - this.nextFrameTime >= FRAME_MILLISECONDS) this.nextFrameTime = now;
    this.runFrame();
    // Include computation in the frame interval. A slow core needs no extra wait.
    this.nextFrameTime = Math.max(this.nextFrameTime + FRAME_MILLISECONDS, this.now());
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
      else this.runFrame();
    } catch (error) {
      this.stop();
      this.emit({ type: 'error', message: error.message });
      return;
    }
    const delay = this.throttleEnabled ? Math.ceil(Math.max(0, this.nextFrameTime - this.now())) : 0;
    this.loopHandle = this.schedule(this.loopTick, delay);
  }
}
