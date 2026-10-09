// Smoke test for the packed ruby.wasm: its /lib files and the shared browser adapter.
// node wasm/test/ruby_wasm.mjs [path/to/rubyboy.wasm]
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DefaultRubyVM } from '../../build/browser-runtime/node_modules/@ruby/wasm-wasi/dist/esm/browser.js';
import { File } from '../../build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/dist/index.js';
import { RubyboyVM } from '../../docs/rubyboy-vm.js';

const repoRoot = fileURLToPath(new URL('../../', import.meta.url));
const hash = bytes => createHash('sha256').update(new Uint8Array(bytes)).digest('hex');
const wasmPath = process.argv[2] || `${repoRoot}docs/rubyboy.wasm`;
const { vm, wasi } = await DefaultRubyVM(await WebAssembly.compile(readFileSync(wasmPath)));
console.log(`Wasm: ${wasmPath} (${vm.eval('RUBY_DESCRIPTION').toString()})`);

// /lib must hold exactly the tracked files, so a stale pack or local saves fail here.
const tracked = execFileSync('git', ['ls-files', '-z', 'lib'], { cwd: repoRoot, encoding: 'utf8' })
  .split('\0').filter(Boolean).sort();
vm.eval("require 'digest/sha2'; require 'json'");
const packed = JSON.parse(vm.eval(`JSON.generate(
  Dir.glob('/lib/**/*', File::FNM_DOTMATCH).select { |path| File.file?(path) }.sort
    .to_h { |path| [path.delete_prefix('/'), Digest::SHA256.file(path).hexdigest] })`).toString());
assert.deepEqual(Object.keys(packed), tracked, 'Packed /lib differs from tracked files');
for (const path of tracked) assert.equal(packed[path], hash(readFileSync(repoRoot + path)), `Stale packed file: ${path}`);

const root = wasi.fds[3].dir;
const core = new RubyboyVM(vm, root, File);
for (const value of ['#{raise "must not execute"}', '"quoted" \\ path 日本語\nnext line']) {
  assert.equal(core.toValue(value).toString(), value, 'Ruby value conversion must preserve literal strings');
}

core.loadUploadedRom(Uint8Array.from(readFileSync(`${repoRoot}lib/roms/tobu.gb`)).buffer);
assert.equal(root.contents.has('rom.data'), false);
let audioBytes = 0;
for (let frame = 0; frame < 60; frame++) {
  core.runFrame(15, 15);
  assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
  audioBytes += core.popAudio()?.byteLength ?? 0;
}
assert.ok(audioBytes > 0, 'The APU must produce audio');
assert.throws(() => core.loadUploadedRom(new ArrayBuffer(5)), /ROM size/);
assert.throws(() => core.loadPreInstalledRom('../other.gb'), /ROM not found in allowed ROMs/);
for (const name of ['tobu.gb', 'bgbtest.gb']) {
  core.loadPreInstalledRom(name);
  core.runFrame(15, 15);
  assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
}
console.log(`PASS ${tracked.length} packed files, adapter, ROM loading and 60 frames`);
