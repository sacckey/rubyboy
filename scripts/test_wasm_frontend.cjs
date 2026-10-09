// Frame pacing, input latching and audio buffering in the shared browser code.
// Run: node scripts/test_wasm_frontend.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const docs = path.resolve(__dirname, '../docs');

const FRAME_MS = 70224 / 4194304 * 1000;

function loopHarness(EmulationLoop, {frameMs = 0, timerTurnaround = 0} = {}) {
  let time = 0;
  let nextTimer = 0;
  let audioDrains = 0;
  const timers = new Map();
  const calls = [];
  const messages = [];
  const frames = [];
  const adapter = {
    runFrame(direction, action) {
      calls.push({direction, action, startedAt: time});
      time += frameMs;
    },
    framebuffer() { const buffer = new ArrayBuffer(160 * 144 * 4); frames.push(buffer); return buffer; },
    popAudio() { audioDrains++; return new Float32Array([.25, -.25]).buffer; },
  };
  const loop = new EmulationLoop(adapter, (message, transfers) => messages.push({message, transfers}), {
    now: () => time,
    setTimeout: (callback, delay) => { timers.set(++nextTimer, {callback, delay}); return nextTimer; },
    clearTimeout: handle => timers.delete(handle),
  });
  function advance(now) {
    time = now;
    const [handle, task] = timers.entries().next().value;
    timers.delete(handle);
    task.callback();
  }
  return {
    loop, adapter, calls, messages, frames, timers,
    drains: () => audioDrains,
    now: () => time,
    nextDelay: () => timers.values().next().value.delay,
    advance,
    runNext() { advance(time + Math.max(timerTurnaround, timers.values().next().value.delay)); },
  };
}

function testClock(EmulationLoop) {
  const fast = loopHarness(EmulationLoop, {frameMs: 2});
  fast.loop.start();
  fast.loop.start();
  assert.equal(fast.timers.size, 1, 'start is idempotent');
  assert.equal(fast.calls.length, 1, 'the first frame is presented immediately');
  assert.equal(fast.nextDelay(), Math.ceil(FRAME_MS - 2), 'execution time is included in the frame interval');
  fast.advance(10);
  assert.equal(fast.calls.length, 1, 'an early timer must not run Ruby');
  assert.equal(fast.drains(), 1);
  fast.advance(FRAME_MS);
  assert.equal(fast.calls.length, 2);
  for (let i = 0; i < 240; i++) fast.runNext();
  const rate = (fast.calls.length - 1) * 1000 / (fast.calls.at(-1).startedAt - fast.calls[0].startedAt);
  assert.ok(rate > 59 && rate <= 60, `fast adapters are capped near the Game Boy frame rate: ${rate}`);
  const fastPixels = fast.messages.filter(item => item.message.type === 'pixelData');
  assert.equal(fastPixels.length, fast.calls.length);
  assert.equal(fast.messages.filter(item => item.message.type === 'audioData').length, 0, 'mute is the default');
  assert.equal(fast.drains(), fast.calls.length, 'audio is drained once per frame');
  fast.loop.stop();
  assert.equal(fast.timers.size, 0, 'stop cancels the loop');

  const paused = loopHarness(EmulationLoop, {frameMs: 2});
  paused.loop.start();
  paused.advance(1000);
  assert.equal(paused.calls.length, 2, 'a one-second timer pause runs one frame, without catching up');
  assert.equal(paused.nextDelay(), Math.ceil(FRAME_MS - 2), 'pause recovery resumes ordinary pacing');
  paused.loop.stop();
  paused.loop.start();
  assert.equal(paused.calls.length, 3, 'restart resets the deadline instead of replaying elapsed time');
  paused.loop.stop();

  const slow = loopHarness(EmulationLoop, {frameMs: 28, timerTurnaround: 4});
  const unlimited = loopHarness(EmulationLoop, {frameMs: 28, timerTurnaround: 4});
  unlimited.loop.setThrottle(false);
  slow.loop.start();
  unlimited.loop.start();
  for (let i = 0; i < 100; i++) {
    assert.equal(slow.nextDelay(), 0, 'a frame slower than the limit incurs no extra wait');
    const before = slow.calls.length;
    slow.runNext();
    unlimited.runNext();
    assert.equal(slow.calls.length, before + 1, 'slow hosts yield after every frame');
  }
  assert.equal(slow.calls.length, unlimited.calls.length);
  assert.equal(slow.now(), unlimited.now(), 'limited slow hosts have the same throughput as unlimited hosts');
  assert.equal(slow.messages.filter(item => item.message.type === 'pixelData').length, slow.calls.length);
  const packet = unlimited.messages.find(item => item.message.type === 'pixelData');
  assert.equal(packet.message.data, unlimited.frames[0]);
  assert.equal(packet.transfers[0], packet.message.data);
  slow.loop.stop();
  unlimited.loop.stop();

  const toggled = loopHarness(EmulationLoop);
  toggled.loop.setMuted(false);
  toggled.loop.start();
  toggled.loop.setThrottle(false);
  toggled.advance(1);
  assert.equal(toggled.calls.length, 2, 'switching off the limit permits the next task');
  assert.equal(toggled.nextDelay(), 0);
  toggled.loop.setThrottle(true);
  toggled.advance(2);
  assert.equal(toggled.calls.length, 3, 'switching on resets the deadline');
  assert.equal(toggled.messages.filter(item => item.message.type === 'audioData').length, 3);
  toggled.advance(3);
  assert.equal(toggled.calls.length, 3, 'subsequent limited tasks respect the new deadline');
  toggled.loop.stop();

  const failed = loopHarness(EmulationLoop);
  failed.adapter.runFrame = () => { throw new Error('emulator failed'); };
  failed.loop.start();
  assert.equal(failed.loop.running, false);
  assert.equal(failed.timers.size, 0);
  assert.equal(failed.messages[0].message.message, 'emulator failed');
}

function testInput(EmulationLoop) {
  const shortPress = loopHarness(EmulationLoop);
  shortPress.loop.start();
  shortPress.loop.setInput(0, 8);
  shortPress.loop.setInput(0, 0);
  shortPress.advance(10);
  assert.equal(shortPress.calls.length, 1, 'a short press survives waiting for the next frame');
  shortPress.runNext();
  assert.equal(shortPress.calls[1].action, 7);
  shortPress.runNext();
  assert.equal(shortPress.calls[2].action, 15, 'the latch clears after the next frame');
  shortPress.loop.setInput(0, 1);
  assert.equal(shortPress.loop.inputMasks()[1], 14, 'the first action bit is active-low');
  shortPress.loop.setInput(0, 3);
  assert.equal(shortPress.loop.inputMasks()[1], 12, 'held action bits combine');
  shortPress.loop.releaseInputs();
  assert.deepEqual(shortPress.loop.inputMasks(), [15, 15]);
  shortPress.loop.stop();
}

function testWorklet() {
  let Processor;
  const context = vm.createContext({
    Float32Array, Math, sampleRate: 48000,
    AudioWorkletProcessor: class { constructor() { this.port = {}; } },
    registerProcessor: (_name, value) => { Processor = value; },
  });
  vm.runInContext(fs.readFileSync(path.join(docs, 'audio-worklet.js'), 'utf8'), context);
  const processor = new Processor();
  const samples = new Float32Array(1024);
  for (let i = 0; i < samples.length; i += 2) { samples[i] = .25; samples[i + 1] = -.25; }
  processor.port.onmessage({ data: samples.buffer });
  const outputs = [[new Float32Array(128), new Float32Array(128)]];
  processor.process([], outputs);
  assert.equal(outputs[0][0][0], .25);
  assert.equal(outputs[0][1][127], -.25, 'stereo channel order is preserved');
  processor.port.onmessage({ data: 'clear' });
  processor.process([], outputs);
  assert.ok(outputs[0].every(channel => channel.every(value => value === 0)), 'cleared/empty audio produces silence');
  processor.port.onmessage({ data: new Float32Array(48000).buffer });
  assert.equal(processor.writeCursor - processor.readCursor, 2047, '500ms burst is bounded below 43ms');
  context.sampleRate = 44100;
  const resampled = new Processor();
  resampled.port.onmessage({ data: samples.buffer });
  resampled.process([], outputs);
  assert.equal(resampled.readCursor, 139, '44.1kHz output resamples 48kHz source duration');
}

(async () => {
  const source = fs.readFileSync(path.join(docs, 'emulation-loop.js'), 'utf8');
  const {EmulationLoop} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  testClock(EmulationLoop);
  testInput(EmulationLoop);
  testWorklet();
  console.log('Wasm frontend tests passed: frame pacing, input latch and audio buffering.');
})().catch(error => { console.error(error); process.exitCode = 1; });
