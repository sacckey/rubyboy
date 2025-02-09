import { DefaultRubyVM } from 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.7.1/dist/browser/+esm';
import { File } from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.3.0/+esm';

const DIRECTION_KEY_MASKS = {
  'KeyD': 0b0001, // Right
  'KeyA': 0b0010, // Left
  'KeyW': 0b0100, // Up
  'KeyS': 0b1000  // Down
};

const ACTION_KEY_MASKS = {
  'KeyK': 0b0001, // A
  'KeyJ': 0b0010, // B
  'KeyU': 0b0100, // Select
  'KeyI': 0b1000  // Start
};

class Rubyboy {
  constructor() {
    this.wasmUrl = 'https://proxy.sacckey.dev/rubyboy.wasm';

    this.directionKey = 0b1111;
    this.actionKey = 0b1111;
  }

  async init() {
    let response = await fetch('./rubyboy.wasm');
    if (!response.ok) {
      response = await fetch(this.wasmUrl);
    }

    const module = await WebAssembly.compileStreaming(response)
    const { vm, wasi } = await DefaultRubyVM(module);
    vm.eval(`
      require 'js'
      require_relative 'lib/executor'

      $executor = Executor.new
    `);

    this.vm = vm;
    this.rootDir = wasi.fds[3].dir
  }

  sendPixelData() {
    this.vm.eval(`$executor.exec(${this.directionKey}, ${this.actionKey})`);

    const file = this.rootDir.contents.get('video.data');
    const bytes = file.data;

    postMessage({ type: 'pixelData', data: bytes.buffer }, [bytes.buffer]);
  }

  emulationLoop() {
    this.sendPixelData();
    setTimeout(this.emulationLoop.bind(this), 0);
  }
}

const rubyboy = new Rubyboy();

self.addEventListener('message', async (event) => {
  if (event.data.type === 'initRubyboy') {
    try {
      await rubyboy.init();
      postMessage({ type: 'initialized', message: 'ok' });
    } catch (error) {
      postMessage({ type: 'error', message: error.message });
    }
  }

  if (event.data.type === 'startRubyboy') {
    try {
      rubyboy.emulationLoop();
    } catch (error) {
      postMessage({ type: 'error', message: error.message });
    }
  }

  if (event.data.type === 'keydown' || event.data.type === 'keyup') {
    const code = event.data.code;
    const directionKeyMask = DIRECTION_KEY_MASKS[code];
    const actionKeyMask = ACTION_KEY_MASKS[code];

    if (directionKeyMask) {
      if (event.data.type === 'keydown') {
        rubyboy.directionKey &= ~directionKeyMask;
      } else {
        rubyboy.directionKey |= directionKeyMask;
      }
    }

    if (actionKeyMask) {
      if (event.data.type === 'keydown') {
        rubyboy.actionKey &= ~actionKeyMask;
      } else {
        rubyboy.actionKey |= actionKeyMask;
      }
    }
  }

  if (event.data.type === 'loadROM') {
    const romFile = new File(new Uint8Array(event.data.data));
    rubyboy.rootDir.contents.set('rom.data', romFile);
    rubyboy.vm.eval(`
      $executor.read_rom_from_virtual_fs
    `);
  }

  if (event.data.type === 'loadPreInstalledRom') {
    rubyboy.vm.eval(`
      $executor.read_pre_installed_rom("${event.data.romName}")
    `);
  }
});
