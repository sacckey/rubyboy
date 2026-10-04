// Verify the Ruby sources and ROMs embedded in the Wasm package.
// node scripts/verify_wasm_package.mjs [WASM_PATH] [EXPECTED_RUBY_VERSION]
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { lstatSync, readFileSync, readdirSync } from 'node:fs';
import { join, relative, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DefaultRubyVM } from '../build/browser-runtime/node_modules/@ruby/wasm-wasi/dist/esm/browser.js';

const repoRoot = fileURLToPath(new URL('../', import.meta.url));
const libRoot = join(repoRoot, 'lib');
const wasmPath = process.argv[2] ? resolve(process.argv[2]) : join(repoRoot, 'docs', 'rubyboy.wasm');
const versionSource = readFileSync(join(libRoot, 'rubyboy', 'version.rb'), 'utf8');
const expectedAppVersion = versionSource.match(/\bVERSION\s*=\s*['"]([^'"]+)['"]/)[1];
const sha256 = bytes => createHash('sha256').update(bytes).digest('hex');

function regularFiles(directory) {
  return readdirSync(directory).sort().flatMap(name => {
    const path = join(directory, name);
    const stat = lstatSync(path);
    if (stat.isDirectory()) return regularFiles(path);
    return stat.isFile() ? [path] : [];
  });
}

const files = regularFiles(libRoot).map(path => {
  const bytes = readFileSync(path);
  return { path: relative(libRoot, path).split('\\').join('/'), size: bytes.length, sha256: sha256(bytes) };
});
assert.ok(files.length > 0, 'Repository lib must contain regular files');
const wasmBytes = readFileSync(wasmPath);
const module = await WebAssembly.compile(wasmBytes);
const { vm } = await DefaultRubyVM(module);

// Read the sources and ROMs packed into the Wasm.
const rubyDescription = vm.eval('RUBY_DESCRIPTION').toString();
assert.equal(vm.eval('RUBY_VERSION').toString(), process.argv[3] || '4.0.7', 'Wasm Ruby version');
vm.eval("require '/lib/rubyboy/version'");
const appVersion = vm.eval('Rubyboy::VERSION').toString();
assert.equal(appVersion, expectedAppVersion, 'Packed Rubyboy version');
vm.eval("require 'digest/sha2'");

vm.eval("require 'json'");
const packedFiles = JSON.parse(vm.eval(
  "JSON.generate(Dir.glob('/lib/**/*', File::FNM_DOTMATCH).select { |path| File.file?(path) }.map { |path| path.delete_prefix('/lib/') }.sort)"
).toString());
assert.deepEqual(packedFiles, files.map(file => file.path).sort(), 'Packed /lib file list differs from repository');

for (const file of files) {
  const packedPath = JSON.stringify(`/lib/${file.path}`);
  const packedSize = Number(vm.eval(`File.size(${packedPath})`).toString());
  assert.equal(packedSize, file.size, `Packed size differs: ${file.path}`);
  const packedHash = vm.eval(`Digest::SHA256.file(${packedPath}).hexdigest`).toString();
  assert.equal(packedHash, file.sha256, `Packed SHA-256 differs: ${file.path}`);
}

console.log(`Wasm: ${wasmPath}`);
console.log(`Wasm SHA-256: ${sha256(wasmBytes)}`);
console.log(`Browser runtime: ${rubyDescription}`);
console.log(`Packed Rubyboy version: ${appVersion}`);
console.log(`PASS packed /lib matches repository: ${files.length} regular files, ${files.filter(file => file.path.endsWith('.rb')).length} Ruby sources, ${files.filter(file => file.path.endsWith('.gb')).length} ROMs, ${files.reduce((sum, file) => sum + file.size, 0)} bytes`);
console.log(`lib manifest SHA-256: ${sha256(files.map(file => `${file.path}\t${file.size}\t${file.sha256}\n`).join(''))}`);
