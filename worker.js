import { RubyVM } from 'https://cdn.jsdelivr.net/npm/@ruby/wasm-wasi@2.6.1/+esm';
import { Directory, File, OpenDirectory, OpenFile, PreopenDirectory, WASI } from 'https://cdn.jsdelivr.net/npm/@bjorn3/browser_wasi_shim@0.3.0/+esm';

class Rubyboy {
  constructor() {
    this.wasmUrl = 'https://proxy.sacckey.dev/rubyboy.wasm';

    const rootContents = new Map();
    rootContents.set('RUBYBOY_TMP', new Directory(new Map()));
    this.rootFs = rootContents

    const args = ["ruby.wasm", "-e_=0"];
    this.wasi = new WASI(args, [], [
      new OpenFile(new File([])), // stdin
      new OpenFile(new File([])), // stdout
      new OpenFile(new File([])), // stderr
      new PreopenDirectory("/", rootContents)
    ], {
      debug: false
    });
    this.count = 0;
    this.lastTime = Date.now();
  }

  async init() {
    let response = await fetch('./rubyboy.wasm');
    if (!response.ok) {
      response = await fetch(this.wasmUrl);
    }

    const buffer = await response.arrayBuffer();
    const imports = {
      wasi_snapshot_preview1: this.wasi.wasiImport,
    };
    const vm = new RubyVM();
    vm.addToImports(imports);

    const { instance } = await WebAssembly.instantiate(buffer, imports);
    await vm.setInstance(instance);
    this.wasi.initialize(instance);
    vm.initialize();

    vm.eval(`
      require 'js'
      require_relative 'lib/executor'

      $executor = Executor.new
    `);

    this.vm = vm;
  }

  sendPixelData() {
    this.vm.eval('$executor.exec');

    this.count += 1;
    if (this.count === 100) {
      console.log('FPS: ', 100 * 1000 / (Date.now() - this.lastTime));
      this.lastTime = Date.now();
      this.count = 0;
    }

    const tmpDir = this.rootFs.get('RUBYBOY_TMP');
    const op = new OpenDirectory(tmpDir);
    const result = op.path_lookup('video.data', 0);
    const file = result.inode_obj;
    const bytes = file.data;

    postMessage({ type: 'pixelData', data: bytes.buffer }, [bytes.buffer]);
  }

  emulationLoop() {
    this.sendPixelData();
    setTimeout(this.emulationLoop.bind(this), 0);
  }
}

self.addEventListener('message', async (event) => {
  if (event.data.type === 'initRubyVM') {
    try {
      const rubyboy = new Rubyboy();
      await rubyboy.init();
      rubyboy.emulationLoop();
    } catch (error) {
      postMessage({ type: 'error', message: error.message });
    }
  }
});
