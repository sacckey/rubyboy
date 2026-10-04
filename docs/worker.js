import { DefaultRubyVM } from 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.10.1/dist/browser/+esm';
import { File, Directory } from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.4.2/+esm';
import { EmulationLoop } from './emulation-loop.js';
import { RubyboyVM, mountCore } from './rubyboy-vm.js';

class Rubyboy {
  constructor() {
    this.wasmUrl = 'https://proxy.sacckey.dev/rubyboy.wasm';
    this.adapter = null;
    this.loop = null;
    this.requestId = 0;
    this.initializing = null;
  }

  async init() {
    // Keep the existing local-first download and proxy fallback.
    let response = await fetch('./rubyboy.wasm');
    if (!response.ok) {
      response = await fetch(this.wasmUrl);
    }
    const module = await WebAssembly.compileStreaming(response);
    const { vm, wasi } = await DefaultRubyVM(module);
    const sources = await fetch('./rubyboy-core.json');
    if (!sources.ok) throw new Error('Ruby source bundle is missing. Run scripts/build-browser-core.rb.');
    const bundle = await sources.json();
    await mountCore(wasi.fds[3].dir, bundle, { File, Directory });
    this.adapter = new RubyboyVM(vm, wasi.fds[3].dir, File);
    this.loop = new EmulationLoop(this.adapter, (message, transfers) => {
      postMessage({ ...message, requestId: this.requestId }, transfers);
    });
    return {
      ruby: vm.eval('RUBY_DESCRIPTION').toString(),
      apiVersion: bundle.api_version,
      sourceHashes: Object.fromEntries(bundle.files.map(file => [file.path, file.sha256])),
    };
  }

  async ensureInitialized() {
    if (!this.initializing) this.initializing = this.init();
    return this.initializing;
  }

  load(data) {
    this.loop.stop();
    if (data.type === 'loadROM') this.adapter.loadUploadedRom(data.data);
    else this.adapter.loadPreInstalledRom(data.romName);
    this.requestId = data.requestId ?? this.requestId + 1;
    this.loop.completedFrames = 0;
    postMessage({ type: 'romLoaded', requestId: this.requestId });
    this.loop.start();
  }
}

const rubyboy = new Rubyboy();
const handlers = {
  async initRubyboy() {
    const runtime = await rubyboy.ensureInitialized();
    postMessage({ type: 'initialized', runtime });
  },
  startRubyboy() { rubyboy.loop.start(); },
  stopRubyboy() { rubyboy.loop.stop(); },
  setThrottle(data) { rubyboy.loop.setThrottle(data.enabled); },
  setMute(data) { rubyboy.loop.setMuted(data.enabled); },
  input(data) { rubyboy.loop.setInput(data.direction, data.action); },
  releaseInputs() { rubyboy.loop.releaseInputs(); },
  keydown(data) { rubyboy.loop.updateInput(data.code, true); },
  keyup(data) { rubyboy.loop.updateInput(data.code, false); },
  loadROM(data) { rubyboy.load(data); },
  loadPreInstalledRom(data) { rubyboy.load(data); },
};

// Initial VM creation and ROM changes must finish before later messages run.
let messages = Promise.resolve();
self.addEventListener('message', ({ data }) => {
  const handler = handlers[data.type];
  if (!handler) return;
  messages = messages.then(() => handler(data)).catch((error) => {
    rubyboy.loop?.stop();
    postMessage({ type: 'error', requestId: data.requestId ?? rubyboy.requestId, message: error.message });
  });
});
