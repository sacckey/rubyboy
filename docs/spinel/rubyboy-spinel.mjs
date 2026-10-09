// Run the Spinel-compiled Rubyboy on browser_wasi_shim, with its bundled files in /.
export async function createRubyboySpinel(module, shim) {
  const preopen = new shim.PreopenDirectory('/', new Map());
  for (const [path, data] of bundledFiles(module)) put(preopen.dir, path, new shim.File(data, { readonly: true }), shim);
  // Spinel opens /dev/null for closed Ruby IO handles.
  put(preopen.dir, '/dev/null', new shim.File([]), shim);
  const wasi = new shim.WASI([], [], [
    new shim.OpenFile(new shim.File([])),
    shim.ConsoleStdout.lineBuffered(line => console.log(line)),
    shim.ConsoleStdout.lineBuffered(line => console.warn(line)),
    preopen,
  ], { debug: false });
  const instance = await WebAssembly.instantiate(module, { wasi_snapshot_preview1: wasi.wasiImport });
  wasi.initialize(instance);
  const exports = instance.exports;

  const check = status => {
    if (!status) return;
    const memory = new Uint8Array(exports.memory.buffer);
    const start = exports.rubyboy_error();
    throw new Error(new TextDecoder().decode(memory.subarray(start, memory.indexOf(0, start))));
  };
  const withString = (value, fn) => {
    const bytes = new TextEncoder().encode(`${value}\0`);
    const pointer = exports.malloc(bytes.length);
    new Uint8Array(exports.memory.buffer, pointer, bytes.length).set(bytes);
    try { return fn(pointer); } finally { exports.free(pointer); }
  };
  withString('/lib/roms/tobu.gb', pointer => check(exports.rubyboy_init(pointer)));
  const executor = {
    call(method, ...args) {
      if (method === 'exec') return check(exports.rubyboy_exec(...args));
      if (method === 'read_rom_from_virtual_fs') return check(exports.rubyboy_read_rom_from_virtual_fs());
      if (method === 'read_pre_installed_rom') return withString(args[0], pointer => check(exports.rubyboy_read_pre_installed_rom(pointer)));
      throw new Error(`Unknown method: ${method}`);
    },
  };
  return { root: preopen.dir, executor };
}

function* bundledFiles(module) {
  for (const section of WebAssembly.Module.customSections(module, 'rubyboy-files')) {
    const view = new DataView(section);
    for (let offset = 0; offset < section.byteLength;) {
      const pathLength = view.getUint32(offset, true);
      const path = new TextDecoder().decode(new Uint8Array(section, offset + 4, pathLength));
      offset += 4 + pathLength;
      const size = view.getUint32(offset, true);
      yield [path, new Uint8Array(section, offset + 4, size)];
      offset += 4 + size;
    }
  }
}

function put(directory, path, file, shim) {
  const parts = path.split('/').filter(Boolean);
  const name = parts.pop();
  for (const part of parts) {
    if (!directory.contents.has(part)) directory.contents.set(part, new shim.Directory(new Map()));
    directory = directory.contents.get(part);
  }
  directory.contents.set(name, file);
}
