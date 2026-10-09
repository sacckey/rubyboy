// Deterministic contracts for the browser layer; real Ruby/Wasm tests are separate.
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

function indexHarness(search = '', {workletLoad = Promise.resolve(), documentUrl = 'http://example.test/rubyboy/'} = {}) {
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
      this.state = 'suspended'; this.options = options; this.resumes = 0; this.suspends = 0; this.modules = [];
      this.audioWorklet = {addModule: url => { this.modules.push(String(url)); return workletLoad; }}; audioContexts.push(this);
    }
    resume() { this.resumes++; this.state = 'running'; return Promise.resolve(); }
    suspend() { this.suspends++; this.state = 'suspended'; return Promise.resolve(); }
  }
  class AudioWorkletNode {
    constructor() { this.messages = []; this.port = {postMessage: message => this.messages.push(message)}; worklets.push(this); }
    connect() {}
  }
  const context = vm.createContext({
    Worker: function(url, options) { worker.url = new URL(url, documentUrl).href; worker.options = {...options}; return worker; },
    URL, URLSearchParams, Map, Promise, Uint8ClampedArray, AudioWorkletNode,
    window: { location: {search}, AudioContext, addEventListener(type, callback) { windowListeners[type] = callback; } },
    document: {
      currentScript: {src: 'http://example.test/rubyboy/index.js'},
      getElementById: id => elements.get(id), querySelectorAll: () => buttons,
      createElement: () => ({getContext: () => canvasContext}),
      addEventListener(type, callback) { (documentListeners[type] ||= []).push(callback); },
    },
    FileReader: class { constructor() { readers.push(this); } readAsArrayBuffer() {} },
    ImageData: class {}, performance: {now: () => 0}, console,
  });
  vm.runInContext(fs.readFileSync(path.join(docs, 'index.js'), 'utf8'), context);
  context.document.currentScript = null;
  function dispatch(type, event) { for (const listener of documentListeners[type] || []) listener(event); }
  function toggle(id, checked) {
    const element = elements.get(id);
    element.checked = checked;
    element.listeners.change({target: element});
  }
  return {messages, worker, elements, buttons, readers, audioContexts, worklets, dispatch, toggle, windowListeners};
}

async function testIndex() {
  for (const documentUrl of ['http://example.test/rubyboy/', 'http://example.test/rubyboy/spinel/']) {
    const reused = indexHarness('', {documentUrl});
    assert.equal(reused.worker.url, new URL('worker.js', documentUrl).href, 'the page selects its own backend worker');
    assert.deepEqual(reused.worker.options, {type: 'module'});
    reused.toggle('mute-toggle', false);
    await new Promise(setImmediate);
    assert.deepEqual(reused.audioContexts[0].modules, ['http://example.test/rubyboy/audio-worklet.js'],
      'both pages load the shared worklet after currentScript becomes null');
  }
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

async function testWorker(EmulationLoop) {
  let listener;
  let loop;
  let frameCalls = 0;
  const timers = new Map();
  const messages = [];
  const adapter = {
    runFrame() { frameCalls++; },
    framebuffer: () => new ArrayBuffer(160 * 144 * 4),
    popAudio: () => null,
    loadUploadedRom() { throw new Error('Unsupported ROM'); },
    async loadPreInstalledRom(name) {
      if (name !== 'tobu.gb') throw new Error('Unknown bundled ROM');
    },
  };
  const context = vm.createContext({
    EmulationLoop: class extends EmulationLoop {
      constructor(adapter, emit) {
        super(adapter, emit, {now: () => 0,
          setTimeout: callback => { timers.set(1, callback); return 1; },
          clearTimeout: handle => timers.delete(handle)});
        loop = this;
      }
    },
    initialize: async () => adapter,
    postMessage: message => messages.push(message),
    self: {addEventListener: (_type, callback) => { listener = callback; }},
  });
  const source = fs.readFileSync(path.join(docs, 'emulation-worker.js'), 'utf8')
    .replace(/^import .*;\n/gm, '').replace('export function', 'function');
  vm.runInContext(source + '\nstartEmulationWorker(initialize);', context);
  const send = async data => { listener({data}); await new Promise(setImmediate); };
  listener({data: {type: 'initRubyboy'}});
  await send({type: 'startRubyboy'});
  assert.equal(messages[0].type, 'initialized', 'initialization precedes queued playback');
  assert.equal(frameCalls, 1);
  for (const data of [{type: 'loadROM'}, {type: 'loadPreInstalledRom', romName: 'missing.gb'}]) {
    await send(data);
    assert.equal(loop.running, true, 'a failed ROM load resumes the previous emulator');
    assert.equal(timers.size, 1, 'recovery schedules exactly one loop');
    assert.equal(messages.at(-2).type, 'error');
    assert.equal(messages.at(-1).type, 'pixelData', 'the old emulator presents another frame');
    assert.equal(messages.filter(message => message.type === 'romLoaded').length, 0);
  }
  loop.stop();
  const pausedFrames = frameCalls;
  await send({type: 'loadROM'});
  assert.equal(loop.running, false, 'a failed load does not resume paused playback');
  assert.equal(frameCalls, pausedFrames);
  assert.equal(timers.size, 0);
  await send({type: 'loadPreInstalledRom', romName: 'tobu.gb'});
  assert.equal(loop.running, true, 'a successful ROM load still starts playback');
  assert.equal(messages.filter(message => message.type === 'romLoaded').length, 1);
  adapter.runFrame = () => { throw new Error('Emulation failed'); };
  loop.stop();
  await send({type: 'startRubyboy'});
  assert.equal(loop.running, false, 'execution errors still stop the loop');
  assert.equal(timers.size, 0);
  assert.equal(messages.at(-1).message, 'Emulation failed');
}

async function testDownload() {
  const source = fs.readFileSync(path.join(docs, 'worker.js'), 'utf8').replace(/^import .*;\n/gm, '');
  for (const statuses of [[200], [404, 200], [404, 503]]) {
    const urls = [];
    let initialize;
    let compiled = false;
    const context = vm.createContext({
      startEmulationWorker: callback => { initialize = callback; },
      fetch: async url => { const status = statuses[urls.length]; urls.push(url); return {ok: status === 200, status}; },
      WebAssembly: {compileStreaming: async response => { assert.equal(response.ok, true); compiled = true; return {}; }},
      DefaultRubyVM: async () => ({vm: {}, wasi: {fds: [null, null, null, {dir: {}}]}}),
      RubyboyVM: class {}, File: class {},
    });
    vm.runInContext(source, context);
    if (statuses.at(-1) === 200) await initialize();
    else await assert.rejects(initialize(), /Wasm download failed \(503\)/);
    assert.equal(compiled, statuses.at(-1) === 200, 'failed responses never reach the Wasm compiler');
    assert.deepEqual(urls, ['./rubyboy.wasm', 'https://proxy.sacckey.dev/rubyboy.wasm'].slice(0, statuses.length));
  }
}

(async () => {
  const source = fs.readFileSync(path.join(docs, 'emulation-loop.js'), 'utf8');
  const {EmulationLoop} = await import('data:text/javascript;base64,' + Buffer.from(source).toString('base64'));
  testClock(EmulationLoop);
  testInput(EmulationLoop);
  testWorklet();
  await testIndex();
  await testWorker(EmulationLoop);
  await testDownload();
  console.log('Wasm frontend tests passed: frame pacing and slow-host throughput, normal/unlimited, input latch and sources, audio transfer/ring/resampling, live playback toggles and startup race, URL defaults, upload race, ROM failure recovery and Wasm download errors.');
})().catch(error => { console.error(error); process.exitCode = 1; });
