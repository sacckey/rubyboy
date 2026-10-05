// Host for Spinel's --ext wasm ABI. Supply @bjorn3/browser_wasi_shim as `shim`.
// createSpinelVM(module, {shim, files}) returns {vm, wasi, root}; calls are synchronous.
// Packed spinel.files entries are read-only; files (Map or object) can add writable files.
const encoder = new TextEncoder();
const decoder = new TextDecoder('utf-8', {ignoreBOM: true});
const strictDecoder = new TextDecoder('utf-8', {fatal: true, ignoreBOM: true});
const TYPES = new Set(['int', 'float', 'bool', 'nil', 'string']);

export class SpinelError extends Error {
  constructor(message) { super(message); this.name = 'SpinelError'; }
}

function pathParts(path, absolute = false) {
  if (typeof path !== 'string' || (absolute && !path.startsWith('/')) || path.includes('\0')) {
    throw new Error('Invalid virtual filesystem path.');
  }
  const parts = path.split('/').filter(Boolean);
  if (!parts.length || parts.some(part => part === '.' || part === '..')) {
    throw new Error('Invalid virtual filesystem path.');
  }
  return parts;
}

function packedFiles(module) {
  const sections = WebAssembly.Module.customSections(module, 'spinel.files');
  if (sections.length > 1) throw new Error('Multiple spinel.files sections.');
  if (!sections.length) return [];
  const bytes = new Uint8Array(sections[0]);
  const view = new DataView(bytes.buffer);
  let offset = 0;
  const take = length => {
    if (length > bytes.length - offset) throw new Error('Truncated spinel.files section.');
    const value = bytes.subarray(offset, offset + length);
    offset += length;
    return value;
  };
  const u32 = () => { const start = offset; take(4); return view.getUint32(start, true); };
  if (u32() !== 1) throw new Error('Unsupported spinel.files version.');
  const count = u32();
  const entries = [];
  const paths = new Set();
  for (let i = 0; i < count; i++) {
    const path = strictDecoder.decode(take(u32()));
    const canonical = '/' + pathParts(path, true).join('/');
    if (paths.has(canonical)) throw new Error('Duplicate packed file: ' + canonical);
    paths.add(canonical);
    entries.push([canonical, take(u32())]);
  }
  if (offset !== bytes.length) throw new Error('Trailing bytes in spinel.files section.');
  return entries;
}

function mount(root, path, file, Directory) {
  const parts = pathParts(path);
  let directory = root;
  for (const name of parts.slice(0, -1)) {
    let child = directory.contents.get(name);
    if (!child) {
      child = new Directory(new Map());
      child.parent = directory;
      directory.contents.set(name, child);
    }
    if (!(child instanceof Directory)) throw new Error('Virtual filesystem parent is not a directory: ' + path);
    directory = child;
  }
  const name = parts.at(-1);
  if (directory.contents.get(name) instanceof Directory) throw new Error('Virtual filesystem path is a directory: ' + path);
  directory.contents.set(name, file);
}

function nullDevice({File, OpenFile, wasi}) {
  class OpenNull extends OpenFile {
    constructor(file, rights, flags) {
      super(file);
      // WASI libc can request zero rights; the shim's File permits IO in that case.
      this.rights = rights || (BigInt(wasi.RIGHTS_FD_READ) | BigInt(wasi.RIGHTS_FD_WRITE));
      this.flags = flags;
    }
    fd_fdstat_get() {
      const fdstat = new wasi.Fdstat(wasi.FILETYPE_CHARACTER_DEVICE, this.flags);
      fdstat.fs_rights_base = this.rights;
      return {ret: wasi.ERRNO_SUCCESS, fdstat};
    }
    fd_read() {
      return {ret: this.rights & BigInt(wasi.RIGHTS_FD_READ) ? wasi.ERRNO_SUCCESS : wasi.ERRNO_BADF, data: new Uint8Array()};
    }
    fd_pread() { return this.fd_read(); }
    fd_write(data) {
      const writable = Boolean(this.rights & BigInt(wasi.RIGHTS_FD_WRITE));
      return {ret: writable ? wasi.ERRNO_SUCCESS : wasi.ERRNO_BADF, nwritten: writable ? data.byteLength : 0};
    }
    fd_pwrite(data) { return this.fd_write(data); }
    fd_seek(_offset, whence) {
      const valid = [wasi.WHENCE_SET, wasi.WHENCE_CUR, wasi.WHENCE_END].includes(whence);
      return {ret: valid ? wasi.ERRNO_SUCCESS : wasi.ERRNO_INVAL, offset: 0n};
    }
    fd_tell() { return {ret: wasi.ERRNO_SUCCESS, offset: 0n}; }
    fd_allocate() { return wasi.ERRNO_SUCCESS; }
    fd_filestat_set_size() { return wasi.ERRNO_SUCCESS; }
  }
  return new class extends File {
    constructor() { super(new Uint8Array()); }
    get size() { return 0n; }
    stat() { return new wasi.Filestat(this.ino, wasi.FILETYPE_CHARACTER_DEVICE, 0n); }
    path_open(_oflags, rights, flags) { return {ret: wasi.ERRNO_SUCCESS, fd_obj: new OpenNull(this, rights, flags)}; }
  }();
}

export class SpinelVM {
  constructor(instance) {
    this.instance = instance;
    this.exports = instance.exports;
    const e = this.exports;
    if (!(e.memory instanceof WebAssembly.Memory)) throw new Error('Spinel module must export memory.');
    for (const name of ['spinel_init', 'spinel_manifest_ptr', 'spinel_manifest_len',
      'spinel_alloc', 'spinel_free', 'spinel_result_int', 'spinel_result_float',
      'spinel_result_ptr', 'spinel_result_len', 'spinel_result_encoding',
      'spinel_error_ptr', 'spinel_error_len']) {
      if (typeof e[name] !== 'function') throw new Error('Missing Spinel ABI export: ' + name);
    }
    if (e.spinel_init() !== 0) throw this.rubyError();
    const manifest = JSON.parse(strictDecoder.decode(this.bytes(e.spinel_manifest_ptr(), e.spinel_manifest_len())));
    if (manifest.version !== 1 || !Array.isArray(manifest.entries)) throw new Error('Unsupported Spinel manifest.');
    this.entries = new Map();
    for (const entry of manifest.entries) {
      if (typeof entry.name !== 'string' || this.entries.has(entry.name) || typeof e[entry.export] !== 'function'
          || !Array.isArray(entry.params) || entry.params.some(type => !TYPES.has(type))
          || (!TYPES.has(entry.result) && entry.result !== 'void')) {
        throw new Error('Invalid Spinel manifest entry.');
      }
      this.entries.set(entry.name, entry);
    }
  }

  bytes(pointer, length) {
    const memory = new Uint8Array(this.exports.memory.buffer);
    const start = pointer >>> 0;
    if (!Number.isInteger(length) || length < 0 || start > memory.length || length > memory.length - start) {
      throw new Error('Invalid Spinel ABI buffer.');
    }
    return memory.slice(start, start + length);
  }

  rubyError() {
    const e = this.exports;
    return new SpinelError(decoder.decode(this.bytes(e.spinel_error_ptr(), e.spinel_error_len())) || 'Ruby call failed.');
  }

  call(name, ...args) { return this.invoke(name, args, false); }

  // Copy raw String bytes even for UTF-8 results (including embedded NULs).
  callBytes(name, ...args) { return this.invoke(name, args, true); }

  invoke(name, args, rawString) {
    const entry = this.entries.get(name);
    if (!entry) throw new Error('Unknown Spinel entry: ' + name);
    if (args.length !== entry.params.length) throw new TypeError('Wrong argument count for ' + name);
    if (rawString && entry.result !== 'string') throw new TypeError('callBytes requires a String result.');
    // Snapshot byte arguments before any native allocation can grow and detach memory.
    const inputs = args.map(value => value instanceof Uint8Array ? value.slice() : value);
    const allocations = [];
    const nativeArgs = [];
    const e = this.exports;
    try {
      entry.params.forEach((type, index) => {
        const value = inputs[index];
        if (type === 'string') {
          if (typeof value !== 'string' && !(value instanceof Uint8Array)) throw new TypeError('Expected String or Uint8Array argument.');
          const data = typeof value === 'string' ? encoder.encode(value) : value;
          if (data.length > 2147483647) throw new RangeError('String argument exceeds the Wasm ABI limit.');
          const pointer = e.spinel_alloc(Math.max(1, data.length)) >>> 0;
          if (!pointer) throw new Error('Spinel argument allocation failed.');
          allocations.push(pointer);
          new Uint8Array(e.memory.buffer).set(data, pointer);
          nativeArgs.push(pointer, data.length, typeof value === 'string' ? 0 : 1);
        } else if (type === 'int') {
          if (!Number.isInteger(value) || value < -2147483648 || value > 2147483647) throw new RangeError('Expected a signed 32-bit Integer argument.');
          nativeArgs.push(value);
        } else if (type === 'float') {
          if (typeof value !== 'number') throw new TypeError('Expected a Float argument.');
          nativeArgs.push(value);
        } else if (type === 'bool') {
          if (typeof value !== 'boolean') throw new TypeError('Expected a Boolean argument.');
          nativeArgs.push(Number(value));
        } else {
          if (value !== null) throw new TypeError('Expected a null argument.');
          nativeArgs.push(0);
        }
      });
      if (e[entry.export](...nativeArgs) !== 0) throw this.rubyError();
      if (entry.result === 'string') {
        const data = this.bytes(e.spinel_result_ptr(), e.spinel_result_len());
        const encoding = e.spinel_result_encoding();
        if (encoding !== 0 && encoding !== 1) throw new Error('Invalid Spinel String encoding.');
        return rawString || encoding === 1 ? data : decoder.decode(data);
      }
      if (entry.result === 'int') return e.spinel_result_int();
      if (entry.result === 'float') return e.spinel_result_float();
      if (entry.result === 'bool') return Boolean(e.spinel_result_int());
      if (entry.result === 'nil') return null;
      return null;
    } finally {
      for (const pointer of allocations) e.spinel_free(pointer);
    }
  }
}

export async function createSpinelVM(module, options = {}) {
  const {WASI, File, Directory, OpenFile, PreopenDirectory, ConsoleStdout} = options.shim || {};
  if ([WASI, File, Directory, OpenFile, PreopenDirectory, ConsoleStdout].some(value => typeof value !== 'function')) {
    throw new TypeError('Supply the browser_wasi_shim module as options.shim.');
  }
  const preopen = new PreopenDirectory('/', new Map());
  const root = preopen.dir;
  for (const [path, data] of packedFiles(module)) mount(root, path, new File(data, {readonly: true}), Directory);
  const files = options.files instanceof Map ? options.files : Object.entries(options.files || {});
  for (const [path, data] of files) {
    const file = data instanceof File ? data : new File(typeof data === 'string' ? encoder.encode(data) : data);
    mount(root, path, file, Directory);
  }
  // Spinel uses a shared /dev/null descriptor for closed Ruby IO handles.
  const dev = root.contents.get('dev');
  if (!(dev instanceof Directory) || !dev.contents.has('null')) {
    mount(root, '/dev/null', nullDevice(options.shim), Directory);
  }
  const env = Array.isArray(options.env) ? options.env : Object.entries(options.env || {}).map(([key, value]) => key + '=' + value);
  const wasi = new WASI(options.args || ['spinel'], env, [
    new OpenFile(new File(options.stdin || new Uint8Array())),
    ConsoleStdout.lineBuffered(options.stdout || (line => console.log(line))),
    ConsoleStdout.lineBuffered(options.stderr || (line => console.error(line))),
    preopen,
  ], {debug: options.debug ?? false});
  const instance = await WebAssembly.instantiate(module, {wasi_snapshot_preview1: wasi.wasiImport});
  wasi.initialize(instance);
  return {vm: new SpinelVM(instance), wasi, root};
}
