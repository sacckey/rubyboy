import { EmulationLoop } from './emulation-loop.js';

export function startEmulationWorker(initialize) {
  class Rubyboy {
    constructor() {
      this.adapter = null;
      this.loop = null;
      this.initializing = null;
    }

    async init() {
      this.adapter = await initialize();
      this.loop = new EmulationLoop(this.adapter, (message, transfers) => postMessage(message, transfers));
    }

    async ensureInitialized() {
      if (!this.initializing) this.initializing = this.init();
      return this.initializing;
    }

    async load(data) {
      const wasRunning = this.loop.running;
      this.loop.stop();
      try {
        if (data.type === 'loadROM') await this.adapter.loadUploadedRom(data.data);
        else await this.adapter.loadPreInstalledRom(data.romName);
      } catch (error) {
        // A rejected ROM leaves the previous emulator usable.
        postMessage({ type: 'error', message: error.message });
        if (wasRunning) this.loop.start();
        return;
      }
      postMessage({ type: 'romLoaded' });
      this.loop.start();
    }
  }

  const rubyboy = new Rubyboy();
  const handlers = {
    async initRubyboy() {
      await rubyboy.ensureInitialized();
      postMessage({ type: 'initialized' });
    },
    startRubyboy() { rubyboy.loop.start(); },
    setThrottle(data) { rubyboy.loop.setThrottle(data.enabled); },
    setMute(data) { rubyboy.loop.setMuted(data.enabled); },
    input(data) { rubyboy.loop.setInput(data.direction, data.action); },
    releaseInputs() { rubyboy.loop.releaseInputs(); },
    loadROM(data) { return rubyboy.load(data); },
    loadPreInstalledRom(data) { return rubyboy.load(data); },
  };

  // Initial VM creation and ROM changes must finish before later messages run.
  let messages = Promise.resolve();
  self.addEventListener('message', ({ data }) => {
    const handler = handlers[data.type];
    if (!handler) return;
    messages = messages.then(() => handler(data)).catch((error) => {
      rubyboy.loop?.stop();
      postMessage({ type: 'error', message: error.message });
    });
  });
}
