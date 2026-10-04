// Deterministic contracts for the browser layer; real Ruby/Wasm tests are separate.
// Run: node scripts/test_wasm_frontend.cjs
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const docs = path.resolve(__dirname, '../docs');

function loopHarness(EmulationLoop, frameResult = 1) {
  let time = 0;
  let cycleRemainder = 0;
  let nextTimer = 0;
  let audioDrains = 0;
  const timers = new Map();
  const calls = [];
  const messages = [];
  const frames = [];
  const adapter = {
    runFrame(direction, action) { calls.push({ direction, action }); return frameResult; },
    runCycles(cycles, direction, action) {
      calls.push({ cycles, direction, action });
      cycleRemainder += cycles;
      const completed = Math.floor(cycleRemainder / 70224);
      cycleRemainder %= 70224;
      return completed;
    },
    framebuffer() { const buffer = new ArrayBuffer(160 * 144 * 4); frames.push(buffer); return buffer; },
    popAudio() { audioDrains++; return new Float32Array([.25, -.25]).buffer; },
  };
  const loop = new EmulationLoop(adapter, (message, transfers) => messages.push({ message, transfers }), {
    now: () => time,
    setTimeout: (callback) => { timers.set(++nextTimer, callback); return nextTimer; },
    clearTimeout: handle => timers.delete(handle),
  });
  return {
    loop, adapter, calls, messages, frames, timers,
    drains: () => audioDrains,
    advance(now) {
      time = now;
      const [handle, callback] = timers.entries().next().value;
      timers.delete(handle);
      callback();
    },
  };
}

function testClock(EmulationLoop) {
  const normal = loopHarness(EmulationLoop);
  normal.loop.start();
  normal.loop.start();
  assert.equal(normal.timers.size, 1, 'start is idempotent');
  assert.equal(normal.calls.length, 0, 'no CPU cycles before wall time advances');
  normal.advance(1000);
  assert.equal(normal.calls.reduce((sum, call) => sum + call.cycles, 0), 4194304 / 4, 'catch-up is limited to 250ms at the exact CPU frequency');
  assert.ok(normal.calls.every(call => call.cycles <= 32768), 'cycle chunks are bounded');
  assert.equal(normal.messages.filter(item => item.message.type === 'pixelData').length, 1, 'normal catch-up sends the latest completed frame once');
  assert.equal(normal.messages.filter(item => item.message.type === 'audioData').length, 0, 'muted is the default');
  assert.equal(normal.drains(), normal.calls.length, 'muted audio is still drained after every CPU chunk');
  normal.loop.stop();
  assert.equal(normal.timers.size, 0, 'stop cancels the loop');
  const coalesced = loopHarness(EmulationLoop);
  coalesced.loop.start();
  coalesced.advance(50.5);
  const coalescedPixels = coalesced.messages.filter(item => item.message.type === 'pixelData');
  assert.equal(coalescedPixels.length, 1, 'three completed PPU frames share one normal presentation');
  assert.equal(coalescedPixels[0].message.frameCount, 3, 'packet records completed frames independently of display arrivals');
  assert.equal(coalescedPixels[0].message.completedFrames, 3, 'packet records cumulative completed frames');
  coalesced.loop.stop();
  const unlimited = loopHarness(EmulationLoop);
  unlimited.loop.setThrottle(false);
  unlimited.loop.setMuted(false);
  unlimited.loop.start();
  assert.equal(unlimited.calls.length, 1, 'unlimited runs one completed-frame call per task');
  unlimited.advance(0);
  assert.equal(unlimited.calls.length, 2);
  const packet = unlimited.messages.find(item => item.message.type === 'pixelData');
  assert.equal(packet.message.data, unlimited.frames[0], 'adapter buffers are transferred without an extra copy');
  assert.equal(packet.transfers[0], packet.message.data);
  assert.equal(packet.message.frameCount, 1);
  assert.equal(packet.message.completedFrames, 1);
  assert.equal(unlimited.messages.filter(item => item.message.type === 'audioData').length, 2);
  unlimited.loop.stop();
  const lcdOff = loopHarness(EmulationLoop, 0);
  lcdOff.loop.setThrottle(false);
  lcdOff.loop.updateInput('KeyI', true);
  lcdOff.loop.updateInput('KeyI', false);
  lcdOff.loop.start();
  lcdOff.advance(0);
  assert.equal(lcdOff.calls[0].action, 7);
  assert.equal(lcdOff.calls[1].action, 15, 'LCD-off fallback clears a one-frame input latch');
  assert.equal(lcdOff.messages.filter(item => item.message.type === 'pixelData').length, 2, 'LCD-off fallback still presents once per unlimited task');
  assert.equal(lcdOff.messages.find(item => item.message.type === 'pixelData').message.frameCount, 0, 'LCD-off presentation does not count a completed PPU frame');
  lcdOff.loop.stop();
  const failed = loopHarness(EmulationLoop);
  failed.adapter.runFrame = () => { throw new Error('emulator failed'); };
  failed.loop.setThrottle(false);
  failed.loop.start();
  assert.equal(failed.loop.running, false);
  assert.equal(failed.timers.size, 0);
  assert.equal(failed.messages[0].message.message, 'emulator failed');
}

function testInput(EmulationLoop) {
  const shortPress = loopHarness(EmulationLoop);
  shortPress.loop.updateInput('KeyI', true);
  shortPress.loop.updateInput('KeyI', false);
  shortPress.loop.start();
  shortPress.advance(10);
  assert.ok(shortPress.calls.every(call => call.action === 7), 'quick Start press remains active through partial frames');
  const before = shortPress.calls.length;
  shortPress.advance(20);
  assert.equal(shortPress.calls[before].action, 7);
  assert.equal(shortPress.calls.at(-1).action, 15, 'latch clears after a completed frame');
  shortPress.loop.updateInput('KeyK', true);
  assert.equal(shortPress.loop.inputMasks()[1], 14, 'K remains Game Boy A');
  shortPress.loop.updateInput('KeyJ', true);
  assert.equal(shortPress.loop.inputMasks()[1], 12, 'J remains Game Boy B');
  shortPress.loop.releaseInputs();
  assert.deepEqual(shortPress.loop.inputMasks(), [15, 15]);
  shortPress.loop.stop();
  const lcdOff = loopHarness(EmulationLoop);
  lcdOff.adapter.runCycles = (cycles, direction, action) => { lcdOff.calls.push({cycles, direction, action}); return 0; };
  lcdOff.loop.updateInput('KeyI', true);
  lcdOff.loop.updateInput('KeyI', false);
  lcdOff.loop.start();
  lcdOff.advance(100);
  assert.equal(lcdOff.calls[0].action, 7);
  assert.equal(lcdOff.calls.at(-1).action, 15, 'normal LCD-off execution does not retain released input forever');
  lcdOff.loop.stop();
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

function indexHarness(search = '', {workletLoad = Promise.resolve()} = {}) {
  const messages = [];
  const documentListeners = {};
  const windowListeners = {};
  const readers = [];
  const audioContexts = [];
  const worklets = [];
  const elements = new Map();
  for (const id of ['canvas', 'rom-input', 'rom-select-box', 'fps-display', 'rom-upload-button', 'throttle-toggle', 'mute-toggle']) {
    elements.set(id, { width: 320, height: 288, listeners: {}, files: [], classList: {remove() {}},
      addEventListener(type, callback) { this.listeners[type] = callback; } });
  }
  for (const id of ['throttle-toggle', 'mute-toggle']) {
    Object.assign(elements.get(id), {tagName: 'INPUT', type: 'checkbox', checked: true});
  }
  const canvasContext = {scale() {}, fillRect() {}, putImageData() {}, drawImage() {}};
  elements.get('canvas').getContext = () => canvasContext;
  const buttons = ['KeyK', 'KeyJ', 'KeyI', 'KeyU'].map(code => ({ dataset: {code}, listeners: {}, setPointerCapture() {},
    addEventListener(type, callback) { this.listeners[type] = callback; } }));
  const worker = {postMessage: message => messages.push(message)};
  class AudioContext {
    constructor(options) {
      this.state = 'suspended'; this.options = options; this.resumes = 0; this.suspends = 0;
      this.audioWorklet = {addModule: () => workletLoad}; audioContexts.push(this);
    }
    resume() { this.resumes++; this.state = 'running'; return Promise.resolve(); }
    suspend() { this.suspends++; this.state = 'suspended'; return Promise.resolve(); }
  }
  class AudioWorkletNode {
    constructor() { this.messages = []; this.port = {postMessage: message => this.messages.push(message)}; worklets.push(this); }
    connect() {}
  }
  const context = vm.createContext({
    Worker: function() { return worker; }, URLSearchParams, Map, Promise, Uint8ClampedArray, AudioWorkletNode,
    window: { location: {search}, AudioContext, addEventListener(type, callback) { windowListeners[type] = callback; } },
    document: {
      getElementById: id => elements.get(id), querySelectorAll: () => buttons,
      createElement: () => ({getContext: () => canvasContext}),
      addEventListener(type, callback) { (documentListeners[type] ||= []).push(callback); },
    },
    FileReader: class { constructor() { readers.push(this); } readAsArrayBuffer() {} },
    ImageData: class {}, performance: {now: () => 0}, console,
  });
  vm.runInContext(fs.readFileSync(path.join(docs, 'index.js'), 'utf8'), context);
  function dispatch(type, event) { for (const listener of documentListeners[type] || []) listener(event); }
  function toggle(id, checked) {
    const element = elements.get(id);
    element.checked = checked;
    element.listeners.change({target: element});
  }
  return {messages, worker, elements, buttons, readers, audioContexts, worklets, dispatch, toggle, windowListeners};
}

async function testIndex() {
  const normal = indexHarness();
  assert.equal(normal.elements.get('throttle-toggle').checked, true, 'throttle checkbox defaults to checked');
  assert.equal(normal.elements.get('mute-toggle').checked, true, 'mute checkbox defaults to checked');
  normal.worker.onmessage({data: {type: 'initialized'}});
  assert.equal(normal.messages.find(message => message.type === 'setThrottle').enabled, true);
  assert.equal(normal.messages.find(message => message.type === 'setMute').enabled, true);
  const event = code => ({code, target: {tagName: 'BODY'}, preventDefault() {}});
  normal.dispatch('keydown', event('KeyK'));
  assert.equal(normal.messages.at(-1).action, 1);
  const start = normal.buttons.find(button => button.dataset.code === 'KeyI');
  start.listeners.pointerdown({pointerId: 1, preventDefault() {}});
  assert.equal(normal.messages.at(-1).action, 9, 'keyboard and touch/pointer sources combine');
  normal.dispatch('keyup', event('KeyK'));
  assert.equal(normal.messages.at(-1).action, 8, 'keyboard release keeps a held pointer button');
  start.listeners.pointercancel({pointerId: 1});
  assert.equal(normal.messages.at(-1).action, 0);
  const beforeClick = normal.messages.length;
  start.listeners.click({detail: 0});
  assert.equal(normal.messages[beforeClick].action, 8);
  assert.equal(normal.messages[beforeClick + 1].action, 0, 'accessibility/keyboard button click pulses input');
  const beforePointerClick = normal.messages.length;
  start.listeners.click({detail: 1});
  assert.equal(normal.messages.length, beforePointerClick, 'pointer click is not duplicated');
  normal.windowListeners.blur();
  assert.equal(normal.messages.at(-1).type, 'releaseInputs');
  assert.equal(normal.audioContexts.length, 0, 'muted playback does not open an audio device');
  let checkboxDefaultPrevented = false;
  const beforeCheckboxKey = normal.messages.length;
  normal.dispatch('keydown', {code: 'Space', target: normal.elements.get('mute-toggle'),
    preventDefault() { checkboxDefaultPrevented = true; }});
  assert.equal(checkboxDefaultPrevented, false, 'Space can activate a focused checkbox');
  assert.equal(normal.messages.length, beforeCheckboxKey, 'checkbox activation key is not Game Boy input');
  normal.toggle('throttle-toggle', false);
  assert.equal(normal.messages.at(-1).type, 'setThrottle');
  assert.equal(normal.messages.at(-1).enabled, false, 'throttle changes reach the worker immediately');
  normal.toggle('throttle-toggle', true);
  assert.equal(normal.messages.at(-1).enabled, true, 'throttle can be restored without restarting');
  normal.elements.get('rom-input').listeners.change({target: {files: [{}]}});
  normal.elements.get('rom-select-box').listeners.change({target: {value: 'bgbtest.gb'}});
  normal.readers[0].onload({target: {result: new ArrayBuffer(32768)}});
  assert.equal(normal.messages.filter(message => message.type === 'loadROM').length, 0, 'late uploaded file cannot replace a later ROM selection');
  const unlimited = indexHarness('?throttle=0&mute=1');
  assert.equal(unlimited.elements.get('throttle-toggle').checked, false, 'URL throttle override is visible in the checkbox');
  assert.equal(unlimited.elements.get('mute-toggle').checked, true);
  unlimited.worker.onmessage({data: {type: 'initialized'}});
  assert.equal(unlimited.messages.find(message => message.type === 'setThrottle').enabled, false);
  assert.equal(unlimited.messages.find(message => message.type === 'setMute').enabled, true);
  const sound = indexHarness('?throttle=1&mute=0');
  assert.equal(sound.elements.get('throttle-toggle').checked, true);
  assert.equal(sound.elements.get('mute-toggle').checked, false, 'URL mute override is visible in the checkbox');
  sound.worker.onmessage({data: {type: 'initialized'}});
  assert.equal(sound.audioContexts.length, 0, 'audio waits for a user gesture');
  sound.dispatch('keydown', event('KeyI'));
  await new Promise(setImmediate);
  assert.equal(sound.audioContexts[0].resumes, 1, 'first gesture resumes audio before worklet startup');
  const samples = new Float32Array([.25, -.25]).buffer;
  sound.worker.onmessage({data: {type: 'audioData', data: samples}});
  assert.equal(sound.worklets[0].messages[0], samples);
  sound.toggle('mute-toggle', true);
  assert.equal(sound.messages.at(-1).type, 'setMute');
  assert.equal(sound.messages.at(-1).enabled, true, 'mute changes reach the worker immediately');
  await new Promise(setImmediate);
  assert.equal(sound.worklets[0].messages.at(-1), 'clear', 'muting discards queued audio');
  assert.equal(sound.audioContexts[0].state, 'suspended', 'muting suspends the audio device');
  const messagesWhileMuted = sound.worklets[0].messages.length;
  sound.worker.onmessage({data: {type: 'audioData', data: samples}});
  sound.dispatch('keydown', event('KeyK'));
  await new Promise(setImmediate);
  assert.equal(sound.worklets[0].messages.length, messagesWhileMuted, 'muted playback drops incoming audio');
  assert.equal(sound.audioContexts[0].resumes, 1, 'game input does not resume muted audio');
  sound.toggle('mute-toggle', false);
  assert.equal(sound.messages.at(-1).type, 'setMute');
  assert.equal(sound.messages.at(-1).enabled, false);
  await new Promise(setImmediate);
  assert.equal(sound.audioContexts.length, 1, 'unmuting reuses the audio context');
  assert.equal(sound.worklets.length, 1, 'unmuting reuses the audio processor');
  assert.equal(sound.audioContexts[0].state, 'running', 'unmute gesture resumes the audio device');
  sound.worker.onmessage({data: {type: 'audioData', data: samples}});
  assert.equal(sound.worklets[0].messages.at(-1), samples, 'audio delivery resumes after unmuting');

  const preinit = indexHarness();
  preinit.toggle('throttle-toggle', false);
  preinit.toggle('mute-toggle', false);
  assert.equal(preinit.messages.at(-1).type, 'setMute', 'toggle commands also send while the worker initializes');
  preinit.worker.onmessage({data: {type: 'initialized'}});
  assert.equal(preinit.messages.at(-3).type, 'setThrottle');
  assert.equal(preinit.messages.at(-3).enabled, false, 'initialization uses the current throttle checkbox');
  assert.equal(preinit.messages.at(-2).type, 'setMute');
  assert.equal(preinit.messages.at(-2).enabled, false, 'initialization uses the current mute checkbox');
  assert.equal(preinit.messages.at(-1).type, 'startRubyboy', 'current playback options precede starting the emulator');
  await new Promise(setImmediate);

  let finishWorklet;
  const duringStartup = indexHarness('', {workletLoad: new Promise(resolve => { finishWorklet = resolve; })});
  duringStartup.toggle('mute-toggle', false);
  assert.equal(duringStartup.audioContexts[0].resumes, 1, 'unmute resumes before the worklet download finishes');
  assert.equal(duringStartup.worklets.length, 0);
  duringStartup.toggle('mute-toggle', true);
  finishWorklet();
  await new Promise(setImmediate);
  assert.equal(duringStartup.audioContexts[0].state, 'suspended', 're-muting during worklet startup stays muted');
  assert.equal(duringStartup.worklets[0].messages.at(-1), 'clear', 'a processor created after muting starts with its queue cleared');
  const messagesAfterStartup = duringStartup.worklets[0].messages.length;
  duringStartup.worker.onmessage({data: {type: 'audioData', data: samples}});
  assert.equal(duringStartup.worklets[0].messages.length, messagesAfterStartup);
  duringStartup.toggle('mute-toggle', false);
  await new Promise(setImmediate);
  assert.equal(duringStartup.audioContexts.length, 1);
  assert.equal(duringStartup.worklets.length, 1);
  duringStartup.worker.onmessage({data: {type: 'audioData', data: samples}});
  assert.equal(duringStartup.worklets[0].messages.at(-1), samples, 'audio can resume after muting during startup');
}

(async () => {
  const source = fs.readFileSync(path.join(docs, 'emulation-loop.js'), 'utf8');
  const {EmulationLoop} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  testClock(EmulationLoop);
  testInput(EmulationLoop);
  testWorklet();
  await testIndex();
  console.log('Wasm frontend tests passed: exact clock/catch-up, normal/unlimited, input latch and sources, audio transfer/ring/resampling, live playback toggles and startup race, URL defaults and upload race.');
})().catch(error => { console.error(error); process.exitCode = 1; });
