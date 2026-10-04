// Run after the browser runtime dependencies and docs/rubyboy.wasm are available.
// mise exec ruby@4.0.7 -- node scripts/test_wasm_runtime.mjs [path/to/rubyboy.wasm]
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import { DefaultRubyVM } from '../build/browser-runtime/node_modules/@ruby/wasm-wasi/dist/esm/browser.js';
import { File, Directory } from '../build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/dist/index.js';
import { mountCore, RubyboyVM } from '../docs/rubyboy-vm.js';

const sourceRoot = new URL('../', import.meta.url);
const hash = bytes => createHash('sha256').update(new Uint8Array(bytes)).digest('hex');
const bundleBytes = readFileSync(new URL('docs/rubyboy-core.json', sourceRoot));
const bundle = JSON.parse(bundleBytes);
const romBytes = readFileSync(new URL('lib/roms/tobu.gb', sourceRoot));
const wasmPath = process.argv[2] || fileURLToPath(new URL('docs/rubyboy.wasm', sourceRoot));
const wasmBytes = readFileSync(wasmPath);

for (const file of bundle.files) {
  const source = readFileSync(new URL(`lib/${file.path}`, sourceRoot));
  assert.equal(source.toString(), file.source, `Regenerate the browser core: ${file.path}`);
  assert.equal(hash(source), file.sha256, `Source SHA-256: ${file.path}`);
}

const referenceProcess = spawnSync('ruby', [fileURLToPath(new URL('wasm_reference.rb', import.meta.url))], {
  cwd: fileURLToPath(sourceRoot), encoding: 'utf8', maxBuffer: 1024 * 1024,
});
assert.equal(referenceProcess.status, 0, referenceProcess.stderr || 'CRuby reference failed');
const reference = JSON.parse(referenceProcess.stdout);
assert.equal(hash(romBytes), reference.rom_sha256);

console.log(`Host: ${reference.ruby}`);
console.log(`Wasm: ${wasmPath}`);
console.log(`Wasm SHA-256: ${hash(wasmBytes)}`);
console.log(`Ruby core bundle SHA-256: ${hash(bundleBytes)} (${bundle.files.length} source files)`);
console.log(`ROM SHA-256: ${reference.rom_sha256}`);

const module = await WebAssembly.compile(wasmBytes);
const { vm, wasi } = await DefaultRubyVM(module);
const root = wasi.fds[3].dir;
await mountCore(root, bundle, { File, Directory });
const core = new RubyboyVM(vm, root, File);
console.log(`Browser runtime: ${vm.eval('RUBY_DESCRIPTION').toString()}`);
const bundledRom = Buffer.from(vm.eval("File.binread('/lib/roms/tobu.gb').unpack1('H*')").toString(), 'hex');
assert.equal(hash(bundledRom), hash(romBytes), 'The default packed ROM must match the repository ROM');
assert.equal(vm.eval('Executor.instance_method(:exec_cycles).source_location.first').toString(),
  '/rubyboy-core/lib/executor.rb');

// Reject corrupted generated sources before Ruby loads them.
const corrupted = structuredClone(bundle);
corrupted.files[0].source += '\n# altered';
await assert.rejects(mountCore(new Directory(new Map()), corrupted, { File, Directory }), /hash mismatch/);

for (const scenario of reference.scenarios) {
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
    const audio = [];
    if (scenario.mode === 'frame') {
      frames += core.runFrame(direction, action);
      const block = core.popAudio();
      if (block) audio.push(Buffer.from(block));
    } else {
      for (const budget of reference.cycle_budgets) {
        frames += core.runCycles(budget, direction, action);
        const block = core.popAudio();
        if (block) audio.push(Buffer.from(block));
      }
    }
    const tickAudio = Buffer.concat(audio);
    accumulatedAudio.push(tickAudio);
    audioBytes += tickAudio.length;
    assert.equal(core.popAudio(), null, 'An audio block must be consumed only once');
    const expected = scenario.checkpoints.find(checkpoint => checkpoint.tick === tick);
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
    assert.deepEqual(actual, expected, `${scenario.mode} checkpoint ${tick}`);
    // The worker transfers this copy; transfer must leave the WASI source usable.
    const transfer = structuredClone(video, { transfer: [video] });
    assert.equal(video.byteLength, 0);
    assert.equal(hash(videoFile.data), hash(transfer));
    console.log(`PASS ${scenario.mode}: tick ${tick}, ${frames} frames, ${audioBytes} audio bytes`);
  }
  assert.ok(audioBytes > 0, 'The APU must produce stereo audio');
}

// Tiny budgets must account for instruction overshoot instead of executing once per tick.
core.loadUploadedRom(Uint8Array.from(romBytes).buffer);
const budgets = [1, 3, 7, 8192];
for (const budget of budgets) core.runCycles(budget, 14, 13);
const splitState = vm.eval('Marshal.dump($executor.instance_variable_get(:@emulator)).bytes.join(",")').toString();
core.loadUploadedRom(Uint8Array.from(romBytes).buffer);
core.runCycles(budgets.reduce((sum, budget) => sum + budget, 0), 14, 13);
assert.equal(vm.eval('Marshal.dump($executor.instance_variable_get(:@emulator)).bytes.join(",")').toString(), splitState);
assert.throws(() => core.runCycles(32769, 15, 15), /Invalid cycle budget/);
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

// Existing packed ROM names remain available with the unique source mount.
core.loadPreInstalledRom('tobu.gb');
core.runFrame(15, 15);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
core.loadPreInstalledRom('bgbtest.gb');
core.runFrame(15, 15);
assert.equal(core.framebuffer().byteLength, 160 * 144 * 4);
console.log('PASS source overlay, audio consumption, buffer transfer, split budgets, LCD-off, and bundled ROMs');
