// Calls the Ruby Executor in either build and moves its output out of the WASI file system.
// Without an executor option, it creates one in the ruby.wasm VM.
export class RubyboyVM {
  constructor(vm, root, File, { executor, toValue } = {}) {
    this.root = root;
    this.File = File;
    this.toValue = toValue || (value => vm.wrap(value).call(typeof value === 'number' ? 'to_i' : 'to_s'));
    this.executor = executor || vm.eval(`
      require 'js'
      require '/lib/executor'
      $executor = Executor.new
    `);
    this.inputValues = Array.from({ length: 16 }, (_, value) => this.toValue(value));
  }

  runFrame(direction, action) {
    this.executor.call('exec', this.inputValues[direction], this.inputValues[action]);
  }

  framebuffer() {
    const file = this.root.contents.get('video.data');
    if (!file || file.data.length !== 160 * 144 * 4) throw new Error('Invalid framebuffer.');
    // Transfer a copy so the WASI filesystem keeps a usable buffer.
    const buffer = file.data.slice().buffer;
    this.root.contents.delete('video.data');
    return buffer;
  }

  popAudio() {
    const file = this.root.contents.get('audio.data');
    if (!file) return null;
    this.root.contents.delete('audio.data');
    return file.data.slice().buffer;
  }

  clearOutputs() {
    this.root.contents.delete('video.data');
    this.root.contents.delete('audio.data');
  }

  loadUploadedRom(data) {
    const bytes = new Uint8Array(data);
    if (bytes.length < 32768 || bytes.length > 8 * 1024 * 1024) throw new Error('ROM size must be 32 KiB to 8 MiB.');
    this.root.contents.set('rom.data', new this.File(bytes));
    try {
      this.executor.call('read_rom_from_virtual_fs');
      this.clearOutputs();
    } finally {
      this.root.contents.delete('rom.data');
    }
  }

  loadPreInstalledRom(name) {
    this.executor.call('read_pre_installed_rom', this.toValue(name));
    this.clearOutputs();
  }
}
