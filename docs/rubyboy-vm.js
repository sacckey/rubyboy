// The downloaded module supplies CRuby; this bundle supplies the current core.
// A unique mount avoids the older /lib files embedded by wasi-vfs.
const CORE_PATH = '/rubyboy-core/lib';
const ROM_NAMES = new Set(['tobu.gb', 'bgbtest.gb']);

function directoryAt(root, components, Directory) {
  let directory = root;
  for (const component of components) {
    if (!directory.contents.has(component)) directory.contents.set(component, new Directory(new Map()));
    directory = directory.contents.get(component);
  }
  return directory;
}

export async function mountCore(root, bundle, { File, Directory }) {
  if (bundle.api_version !== 1 || !Array.isArray(bundle.files)) {
    throw new Error('Unsupported Ruby core bundle. Run scripts/build-browser-core.rb.');
  }
  const encoder = new TextEncoder();
  for (const file of bundle.files) {
    if (!/^(?:[a-z0-9_]+\/)*[a-z0-9_]+\.rb$/.test(file.path) || typeof file.source !== 'string') {
      throw new Error('Invalid Ruby core source path.');
    }
    const bytes = encoder.encode(file.source);
    const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', bytes));
    const digest = [...hash].map(value => value.toString(16).padStart(2, '0')).join('');
    if (digest !== file.sha256) throw new Error(`Ruby source hash mismatch: ${file.path}`);
    const components = ['rubyboy-core', 'lib', ...file.path.split('/')];
    const name = components.pop();
    directoryAt(root, components, Directory).contents.set(name, new File(bytes));
  }
}

export class RubyboyVM {
  constructor(vm, root, File) {
    this.vm = vm;
    this.root = root;
    this.File = File;
    this.executor = vm.eval(`
      require 'js'
      $LOAD_PATH.unshift('${CORE_PATH}')
      require '${CORE_PATH}/executor'
      $executor = Executor.new
    `);
    this.inputValues = Array.from({ length: 16 }, (_, value) => vm.eval(String(value)));
    this.fullBudget = vm.eval('32768');
  }

  runFrame(direction, action) {
    return Number(this.executor.call('exec', this.inputValues[direction], this.inputValues[action]).toString());
  }

  runCycles(cycles, direction, action) {
    if (!Number.isInteger(cycles) || cycles <= 0 || cycles > 32768) throw new Error('Invalid cycle budget.');
    const budget = cycles === 32768 ? this.fullBudget : this.vm.eval(String(cycles));
    return Number(this.executor.call('exec_cycles', budget, this.inputValues[direction], this.inputValues[action]).toString());
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
    if (!ROM_NAMES.has(name)) throw new Error('Unknown bundled ROM.');
    this.executor.call('read_pre_installed_rom', this.vm.eval(JSON.stringify(name)));
    this.clearOutputs();
  }
}
