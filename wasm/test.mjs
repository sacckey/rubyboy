// Execute both backends through the shared RubyboyVM and compare Ruby outputs.
// node --experimental-wasm-exnref wasm/test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import * as shim from '../build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/dist/index.js';
import { createSpinelVM } from '../docs/spinel/spinel-vm.mjs';
import { RubyboyVM } from '../docs/rubyboy-vm.js';

const hash = bytes => createHash('sha256').update(new Uint8Array(bytes)).digest('hex');
const native = spawnSync(process.env.RUBY || 'ruby', ['scripts/wasm_reference.rb'], {
  encoding: 'utf8', maxBuffer: 1024 * 1024,
});
assert.equal(native.status, 0, native.stderr);
const reference = JSON.parse(native.stdout);
const bytes = readFileSync('docs/spinel/rubyboy-spinel.wasm');
const module = await WebAssembly.compile(bytes);
assert(WebAssembly.Module.imports(module).every(entry => entry.module === 'wasi_snapshot_preview1'));
const { vm, root } = await createSpinelVM(module, { shim });
assert.equal(vm.call('RubyboyBrowser.init', '/lib/roms/tobu.gb'), true);
const executor = { call: (method, ...args) => vm.call(`RubyboyBrowser.${method}`, ...args) };
const core = new RubyboyVM(vm, root, shim.File, { executor, toValue: value => value });
const roms = root.contents.get('lib').contents.get('roms');
const info = JSON.parse(readFileSync('docs/spinel/build-info.json'));
// Only Git-tracked ROM files are embedded; local saves and states must not be.
const embedded = dir => [...dir.contents].flatMap(([name, entry]) =>
  entry instanceof shim.File ? [name] : embedded(entry).map(path => `${name}/${path}`));
const tracked = spawnSync('git', ['ls-files', '-z', 'lib/roms'], { encoding: 'utf8' }).stdout.split('\0').filter(Boolean);
assert.deepEqual(embedded(roms).map(path => `lib/roms/${path}`).sort(), tracked.sort());
for (const entry of info.roms) {
  const relative = entry.path.slice('/lib/roms/'.length);
  let file = roms;
  for (const part of relative.split('/')) file = file.contents.get(part);
  assert(file instanceof shim.File && file.readonly);
  assert.equal(file.data.length, entry.bytes);
  assert.equal(hash(file.data), entry.sha256);
  assert.equal(hash(file.data), hash(readFileSync('lib/roms/' + relative)));
}
assert.equal(info.executor_sha256, hash(readFileSync('lib/executor.rb')));
assert.equal(info.emulator_sha256, hash(readFileSync('lib/rubyboy/emulator_wasm.rb')));
assert.equal(info.wasm_sha256, hash(bytes));
const rom = readFileSync('lib/roms/tobu.gb');
core.loadUploadedRom(Uint8Array.from(rom).buffer);
assert.equal(root.contents.has('rom.data'), false);
assert.equal(core.popAudio(), null);
const accumulated = [];
let audioBytes = 0;
for (let tick = 1; tick <= reference.ticks; tick++) {
  const [direction, action] = reference.inputs[tick - 1];
  core.runFrame(direction, action);
  const block = core.popAudio();
  const audio = block ? Buffer.from(block) : Buffer.alloc(0);
  accumulated.push(audio);
  audioBytes += audio.length;
  assert.equal(core.popAudio(), null);
  const expected = reference.checkpoints.find(entry => entry.tick === tick);
  if (!expected) continue;
  const file = root.contents.get('video.data');
  const video = core.framebuffer();
  assert.deepEqual({ tick, video_sha256: hash(video),
    audio_sha256: hash(audio), audio_bytes: audio.length,
    accumulated_audio_sha256: hash(Buffer.concat(accumulated)),
    accumulated_audio_bytes: audioBytes }, expected, `frame tick ${tick}`);
  const transferred = structuredClone(video, { transfer: [video] });
  assert.equal(video.byteLength, 0);
  assert.equal(hash(transferred), hash(file.data));
}
assert(audioBytes > 0);
console.log(`PASS frame: identical Ruby framebuffer/audio bytes at six checkpoints`);
for (const name of ['tobu.gb', 'bgbtest.gb']) {
  core.loadPreInstalledRom(name);
  core.runFrame(15, 15);
  assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
}
assert.throws(() => core.loadPreInstalledRom('../other.gb'), /Unknown bundled ROM/);
assert.throws(() => core.loadUploadedRom(new ArrayBuffer(5)), /ROM size/);
const unsupported = Uint8Array.from(rom);
unsupported[0x147] = 0xff;
assert.throws(() => core.loadUploadedRom(unsupported.buffer));
assert.equal(root.contents.has('rom.data'), false);
core.loadUploadedRom(Uint8Array.from(rom).buffer);
for (let frame = 0; frame < 1500; frame++) {
  core.runFrame(15, 15);
  assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
  core.popAudio();
}
const lcdOff = Uint8Array.from(rom.subarray(0, 32768));
lcdOff[0x147] = lcdOff[0x148] = lcdOff[0x149] = 0;
lcdOff.set([0xc3, 0x50, 0x01], 0x100);
lcdOff.set([0x3e, 0, 0xe0, 0x40, 0x18, 0xfe], 0x150);
core.loadUploadedRom(lcdOff.buffer);
core.runFrame(15, 15);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
assert(core.popAudio().byteLength > 0);
console.log(`PASS embedded files, unchanged Executor, shared adapter, ROM/error recovery, LCD-off and 1500 frames (${bytes.length.toLocaleString()} bytes)`);
