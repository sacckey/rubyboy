// Run after the browser runtime dependencies and docs/rubyboy.wasm are available.
// mise exec ruby@4.0.7 -- node scripts/test_wasm_runtime.mjs [path/to/rubyboy.wasm]
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DefaultRubyVM } from '../build/browser-runtime/node_modules/@ruby/wasm-wasi/dist/esm/browser.js';
import { File } from '../build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/dist/index.js';
import { RubyboyVM } from '../docs/rubyboy-vm.js';

const sourceRoot = new URL('../', import.meta.url);
const hash = bytes => createHash('sha256').update(new Uint8Array(bytes)).digest('hex');
const romBytes = readFileSync(new URL('lib/roms/tobu.gb', sourceRoot));
const wasmPath = process.argv[2] || fileURLToPath(new URL('docs/rubyboy.wasm', sourceRoot));
const wasmBytes = readFileSync(wasmPath);

const referenceProcess = spawnSync('ruby', [fileURLToPath(new URL('wasm_reference.rb', import.meta.url))], {
  cwd: fileURLToPath(sourceRoot), encoding: 'utf8', maxBuffer: 1024 * 1024,
});
assert.equal(referenceProcess.status, 0, referenceProcess.stderr || 'CRuby reference failed');
const reference = JSON.parse(referenceProcess.stdout);
assert.equal(hash(romBytes), reference.rom_sha256);

console.log(`Host: ${reference.ruby}`);
console.log(`Wasm: ${wasmPath}`);
console.log(`Wasm SHA-256: ${hash(wasmBytes)}`);
console.log(`ROM SHA-256: ${reference.rom_sha256}`);

const module = await WebAssembly.compile(wasmBytes);
const { vm, wasi } = await DefaultRubyVM(module);
const root = wasi.fds[3].dir;
const core = new RubyboyVM(vm, root, File);
for (const value of ['#{raise "must not execute"}', '"quoted" \\ path 日本語\nnext line']) {
  assert.equal(core.toValue(value).toString(), value, 'Ruby value conversion must preserve literal strings');
}
console.log(`Browser runtime: ${vm.eval('RUBY_DESCRIPTION').toString()}`);
const bundledRom = Buffer.from(vm.eval("File.binread('/lib/roms/tobu.gb').unpack1('H*')").toString(), 'hex');
assert.equal(hash(bundledRom), hash(romBytes), 'The default packed ROM must match the repository ROM');
assert.equal(vm.eval('Executor.instance_method(:exec).source_location.first').toString(),
  '/lib/executor.rb');

// Upload the current repository ROM so the old packed asset cannot change the fixture.
core.loadUploadedRom(Uint8Array.from(romBytes).buffer);
assert.equal(root.contents.has('rom.data'), false);
assert.equal(root.contents.has('video.data'), false);
assert.equal(core.popAudio(), null);
const accumulatedAudio = [];
let frames = 0;
let audioBytes = 0;
for (let tick = 1; tick <= reference.ticks; tick++) {
  const [direction, action] = reference.inputs[tick - 1];
  frames += core.runFrame(direction, action);
  const block = core.popAudio();
  const tickAudio = block ? Buffer.from(block) : Buffer.alloc(0);
  accumulatedAudio.push(tickAudio);
  audioBytes += tickAudio.length;
  assert.equal(core.popAudio(), null, 'An audio block must be consumed only once');
  const expected = reference.checkpoints.find(checkpoint => checkpoint.tick === tick);
  if (!expected) continue;
  const videoFile = root.contents.get('video.data');
  assert.equal(videoFile?.data.length, 160 * 144 * 4);
  const video = core.framebuffer();
  assert.equal(root.contents.has('video.data'), false);
  const actual = {
    tick, frames, video_sha256: hash(video),
    audio_sha256: hash(tickAudio), audio_bytes: tickAudio.length,
    accumulated_audio_sha256: hash(Buffer.concat(accumulatedAudio)),
    accumulated_audio_bytes: audioBytes,
  };
  assert.deepEqual(actual, expected, `frame checkpoint ${tick}`);
  // The worker transfers this copy; transfer must leave the WASI source usable.
  const transfer = structuredClone(video, { transfer: [video] });
  assert.equal(video.byteLength, 0);
  assert.equal(hash(videoFile.data), hash(transfer));
  console.log(`PASS frame: tick ${tick}, ${frames} frames, ${audioBytes} audio bytes`);
}
assert.ok(audioBytes > 0, 'The APU must produce stereo audio');

assert.throws(() => core.loadUploadedRom(new ArrayBuffer(5)), /ROM size/);
assert.throws(() => core.loadPreInstalledRom('../other.gb'), /Unknown bundled ROM/);

// Disabling the LCD must not trap the browser worker in a frame wait.
core.loadUploadedRom(Uint8Array.from(romBytes).buffer);
vm.eval('$executor.instance_variable_get(:@emulator).instance_variable_get(:@ppu).write_byte(0xff40, 0)');
assert.equal(core.runFrame(15, 15), 1);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
assert.ok(core.popAudio().byteLength > 0);
core.clearOutputs();
assert.equal(core.popAudio(), null);
assert.equal(root.contents.has('video.data'), false);

// Existing ROMs and Ruby sources are packed together under /lib.
core.loadPreInstalledRom('tobu.gb');
core.runFrame(15, 15);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
core.loadPreInstalledRom('bgbtest.gb');
core.runFrame(15, 15);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
console.log('PASS packed sources, audio consumption, buffer transfer, LCD-off, and bundled ROMs');
