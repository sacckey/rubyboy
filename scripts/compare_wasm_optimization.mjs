// Fixed comparison, prepared before observing results. No source or UI changes.
// node scripts/compare_wasm_optimization.mjs BASELINE.wasm CANDIDATE.wasm [OUTPUT.json]
import assert from 'node:assert/strict';
import { createHash, webcrypto } from 'node:crypto';
import { lstatSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { performance } from 'node:perf_hooks';
import { arch, cpus, platform, release } from 'node:os';
import { resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { DefaultRubyVM } from '../build/browser-runtime/node_modules/@ruby/wasm-wasi/dist/esm/browser.js';
import { File } from '../build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/dist/index.js';
import { RubyboyVM } from '../docs/rubyboy-vm.js';

if (!globalThis.crypto) globalThis.crypto = webcrypto;
const REPO = resolve(fileURLToPath(new URL('../', import.meta.url)));
const SCRIPT = fileURLToPath(import.meta.url);
const LIB_PATH = `${REPO}/lib`;
const ROM_PATH = `${REPO}/lib/roms/tobu.gb`;
const SDK_PACKAGE_PATH = `${REPO}/build/browser-runtime/node_modules/@ruby/wasm-wasi/package.json`;
const SHIM_PACKAGE_PATH = `${REPO}/build/browser-runtime/node_modules/@bjorn3/browser_wasi_shim/package.json`;
const ADAPTER_PATH = `${REPO}/docs/rubyboy-vm.js`;
const TRIAL_MARKER = 'RUBYBOY_OPT_TRIAL_JSON ';
const CONDITIONS = Object.freeze({
  warmup_run_frame_calls: 300,
  measured_run_frame_calls: 600,
  paired_trials: 5,
  orders: [['baseline', 'candidate'], ['candidate', 'baseline'], ['baseline', 'candidate'], ['candidate', 'baseline'], ['baseline', 'candidate']],
  direction_mask: 15,
  action_mask: 15,
  apu_enabled: true,
  transfer_audio: true,
  transfer_framebuffer: true,
  timed_operations: 'core.runFrame -> core.popAudio -> transfer audio -> core.framebuffer -> transfer framebuffer',
  timer: 'performance.now; one timer around all 600 calls and their VFS copies/transfers',
  hash_work_in_timed_region: false,
  rom: ROM_PATH,
  packed_sources: '/lib',
  ruby_version: '4.0.7',
  sdk_version: '2.10.1',
  wasi_shim_version: '0.4.2',
  fresh_process_and_default_ruby_vm_per_trial: true,
  concurrent_trials: false,
  candidate_command: 'wasm-opt baseline --strip-dwarf -O4 --converge -g -o candidate',
  acceptance: 'All final framebuffer, full measured Float32 stereo audio, and final Marshal state hashes match across every trial; all five candidate trials are faster than their paired baseline; median paired FPS speedup is at least 5%. Otherwise retain baseline.',
  min_median_paired_speedup_percent: 5,
  cold_measurement_scope: 'First WebAssembly.compile in each fresh Node process; VM init, adapter construction and ROM upload timed separately. Node startup, JS imports, file reads, and network transfer excluded.',
});

const hash = bytes => createHash('sha256').update(new Uint8Array(bytes)).digest('hex');
const median = values => [...values].sort((a, b) => a - b)[Math.floor(values.length / 2)];

function fixtures() {
  const sdkPackage = JSON.parse(readFileSync(SDK_PACKAGE_PATH));
  const shimPackage = JSON.parse(readFileSync(SHIM_PACKAGE_PATH));
  assert.equal(sdkPackage.version, CONDITIONS.sdk_version, 'Pin the original Ruby SDK to 2.10.1');
  assert.equal(shimPackage.version, CONDITIONS.wasi_shim_version, 'Pin the original WASI shim to 0.4.2');
  function sourceFiles(directory, prefix = '') {
    return readdirSync(directory).sort().flatMap(name => {
      const path = `${directory}/${name}`;
      const relative = `${prefix}${name}`;
      if (lstatSync(path).isDirectory()) return sourceFiles(path, `${relative}/`);
      return name.endsWith('.rb') ? [relative] : [];
    });
  }
  const sourceHashes = Object.fromEntries(sourceFiles(LIB_PATH).map(path => [path, hash(readFileSync(`${LIB_PATH}/${path}`))]));
  const romBytes = readFileSync(ROM_PATH);
  return {
    romBytes,
    metadata: {
      source_hashes: sourceHashes,
      rom_sha256: hash(romBytes),
      adapter_sha256: hash(readFileSync(ADAPTER_PATH)),
      benchmark_script_sha256: hash(readFileSync(SCRIPT)),
      sdk: { name: sdkPackage.name, version: sdkPackage.version, package_sha256: hash(readFileSync(SDK_PACKAGE_PATH)) },
      wasi_shim: { name: shimPackage.name, version: shimPackage.version, package_sha256: hash(readFileSync(SHIM_PACKAGE_PATH)) },
    },
  };
}

async function trial(label, pair, wasmPath) {
  const { romBytes, metadata } = fixtures();
  const wasmBytes = readFileSync(wasmPath);
  const compileStart = performance.now();
  const wasmModule = await WebAssembly.compile(wasmBytes);
  const compileMs = performance.now() - compileStart;
  const initStart = performance.now();
  const { vm, wasi } = await DefaultRubyVM(wasmModule);
  const root = wasi.fds[3].dir;
  const core = new RubyboyVM(vm, root, File);
  core.loadUploadedRom(Uint8Array.from(romBytes).buffer);
  const initMs = performance.now() - initStart;

  const rubyVersion = vm.eval('RUBY_VERSION').toString();
  assert.equal(rubyVersion, CONDITIONS.ruby_version);
  const runtime = {
    description: vm.eval('RUBY_DESCRIPTION').toString(),
    version: rubyVersion,
    platform: vm.eval('RUBY_PLATFORM').toString(),
    yjit_enabled: vm.eval('defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false').toString() === 'true',
    zjit_enabled: vm.eval('defined?(RubyVM::ZJIT) ? RubyVM::ZJIT.enabled? : false').toString() === 'true',
    executor_source: vm.eval('Executor.instance_method(:exec).source_location.first').toString(),
  };
  assert.equal(runtime.yjit_enabled, false);
  assert.equal(runtime.zjit_enabled, false);
  assert.equal(runtime.executor_source, '/lib/executor.rb');
  // Validate the actual packed sources before warmup, outside timed operations.
  vm.eval("require 'digest/sha2'");
  for (const [path, expected] of Object.entries(metadata.source_hashes)) {
    const actual = vm.eval(`Digest::SHA256.file(${JSON.stringify(`/lib/${path}`)}).hexdigest`).toString();
    assert.equal(actual, expected, `Packed source differs: ${path}`);
  }

  // Match the unthrottled worker's core, VFS copies, and transferable messages.
  // The audio and final video are retained for checksums after the timer stops.
  function step(retainAudio) {
    const frames = core.runFrame(CONDITIONS.direction_mask, CONDITIONS.action_mask);
    const audio = core.popAudio();
    let receivedAudio = null;
    if (audio && audio.byteLength > 0) {
      receivedAudio = structuredClone({ type: 'audioData', data: audio }, { transfer: [audio] }).data;
    }
    const video = core.framebuffer();
    const receivedVideo = structuredClone({ type: 'pixelData', data: video, frameCount: frames }, { transfer: [video] }).data;
    if (retainAudio && receivedAudio) measuredAudio.push(receivedAudio);
    return { frames, video: receivedVideo };
  }

  const measuredAudio = [];
  const warmupStart = performance.now();
  for (let i = 0; i < CONDITIONS.warmup_run_frame_calls; i++) step(false);
  const warmupMs = performance.now() - warmupStart;

  let frames = 0;
  let finalVideo;
  const measureStart = performance.now();
  for (let i = 0; i < CONDITIONS.measured_run_frame_calls; i++) {
    const output = step(true);
    frames += output.frames;
    finalVideo = output.video;
  }
  const elapsedMs = performance.now() - measureStart;

  assert.equal(frames, CONDITIONS.measured_run_frame_calls, 'The fixed fixture must produce exactly one frame per call');
  assert.equal(finalVideo.byteLength, 160 * 144 * 4);
  const audioHash = createHash('sha256');
  let audioBytes = 0;
  for (const data of measuredAudio) {
    assert.equal(data.byteLength % 8, 0, 'Float32 stereo audio must contain complete sample pairs');
    audioHash.update(new Uint8Array(data));
    audioBytes += data.byteLength;
  }
  assert.ok(audioBytes > 0, 'The APU must remain enabled and produce audio');
  const stateHex = vm.eval('Marshal.dump($executor.instance_variable_get(:@emulator)).unpack1("H*")').toString();
  const stateBytes = Buffer.from(stateHex, 'hex');
  return {
    pair, label, wasm_path: wasmPath, artifact_sha256: hash(wasmBytes), runtime, fixtures: metadata,
    fresh_process_cold_compile_ms: compileMs,
    fresh_vm_init_rom_ms: initMs,
    warmup_ms: warmupMs,
    measured_ms: elapsedMs,
    measured_run_frame_calls: CONDITIONS.measured_run_frame_calls,
    completed_frames: frames,
    emulation_ms_per_frame: elapsedMs / frames,
    emulation_fps: frames * 1000 / elapsedMs,
    final_framebuffer_sha256: hash(finalVideo),
    measured_audio_sha256: audioHash.digest('hex'),
    measured_audio_bytes: audioBytes,
    measured_audio_float32_values: audioBytes / 4,
    measured_audio_stereo_samples: audioBytes / 8,
    measured_audio_blocks: measuredAudio.length,
    final_emulator_marshal_state_sha256: hash(stateBytes),
    final_emulator_marshal_state_bytes: stateBytes.length,
  };
}

function runTrial(label, pair, wasmPath) {
  const child = spawnSync(process.execPath, [SCRIPT, '--internal-trial', label, String(pair), wasmPath], {
    encoding: 'utf8', maxBuffer: 4 * 1024 * 1024,
    env: { ...process.env, RUBYOPT: '', RUBY_YJIT_ENABLE: '', RUBY_ZJIT_ENABLE: '' },
  });
  if (child.status !== 0) throw new Error(`${label} pair ${pair} failed: ${child.error?.message || child.stderr || child.stdout}`);
  const line = child.stdout.split('\n').find(value => value.startsWith(TRIAL_MARKER));
  assert.ok(line, `Missing trial JSON for ${label} pair ${pair}`);
  const result = JSON.parse(line.slice(TRIAL_MARKER.length));
  if (child.stderr.trim()) process.stderr.write(child.stderr);
  return result;
}

function summarize(results) {
  const baseline = results.filter(result => result.label === 'baseline');
  const candidate = results.filter(result => result.label === 'candidate');
  const equalFields = ['completed_frames', 'final_framebuffer_sha256', 'measured_audio_sha256', 'measured_audio_bytes', 'measured_audio_blocks', 'final_emulator_marshal_state_sha256', 'final_emulator_marshal_state_bytes'];
  const checksumMismatches = [];
  for (const result of results) {
    for (const field of equalFields) {
      if (result[field] !== results[0][field]) checksumMismatches.push({ pair: result.pair, label: result.label, field, expected: results[0][field], actual: result[field] });
    }
  }
  const pairs = Array.from({ length: CONDITIONS.paired_trials }, (_, index) => {
    const pair = index + 1;
    const b = baseline.find(result => result.pair === pair);
    const c = candidate.find(result => result.pair === pair);
    return {
      pair, order: CONDITIONS.orders[index],
      baseline_ms: b.measured_ms, candidate_ms: c.measured_ms,
      baseline_fps: b.emulation_fps, candidate_fps: c.emulation_fps,
      candidate_faster: c.measured_ms < b.measured_ms,
      fps_speedup_percent: (b.measured_ms / c.measured_ms - 1) * 100,
      time_reduction_percent: (1 - c.measured_ms / b.measured_ms) * 100,
    };
  });
  const allPairsFaster = pairs.every(pair => pair.candidate_faster);
  const medianPairedSpeedupPercent = median(pairs.map(pair => pair.fps_speedup_percent));
  const checksumsEqual = checksumMismatches.length === 0;
  const accepted = checksumsEqual && allPairsFaster && medianPairedSpeedupPercent >= CONDITIONS.min_median_paired_speedup_percent;
  return {
    pairs, checksums_equal: checksumsEqual, checksum_mismatches: checksumMismatches,
    all_five_pairs_candidate_faster: allPairsFaster,
    median_paired_fps_speedup_percent: medianPairedSpeedupPercent,
    baseline_median_ms: median(baseline.map(result => result.measured_ms)),
    candidate_median_ms: median(candidate.map(result => result.measured_ms)),
    baseline_median_fps: median(baseline.map(result => result.emulation_fps)),
    candidate_median_fps: median(candidate.map(result => result.emulation_fps)),
    accept_candidate: accepted,
    selection: accepted ? 'candidate' : 'baseline',
  };
}

if (process.argv[2] === '--internal-trial') {
  const [, , , label, pair, wasmPath] = process.argv;
  try {
    const result = await trial(label, Number(pair), wasmPath);
    console.log(TRIAL_MARKER + JSON.stringify(result));
  } catch (error) {
    console.error(error.stack || String(error));
    process.exitCode = 1;
  }
} else {
  const [baselineArg, candidateArg, jsonArg] = process.argv.slice(2);
  if (!baselineArg || !candidateArg || process.argv.length > 5) {
    console.error(`Usage: node ${SCRIPT} BASELINE.wasm CANDIDATE.wasm [OUTPUT.json]`);
    process.exitCode = 2;
  } else {
    const baselinePath = resolve(baselineArg);
    const candidatePath = resolve(candidateArg);
    const outputPath = jsonArg ? resolve(jsonArg) : null;
    const initialFixtures = fixtures().metadata;
    const artifacts = { baseline: { path: baselinePath, sha256: hash(readFileSync(baselinePath)) }, candidate: { path: candidatePath, sha256: hash(readFileSync(candidatePath)) } };
    assert.notEqual(artifacts.baseline.sha256, artifacts.candidate.sha256, 'Candidate and baseline artifacts must differ');
    const report = {
      schema_version: 2, created_at: new Date().toISOString(), conditions: CONDITIONS,
      environment: { node: process.version, versions: process.versions, platform: platform(), arch: arch(), os_release: release(), cpu: cpus()[0]?.model, logical_cpus: cpus().length },
      fixtures: initialFixtures, artifacts, trials: [],
    };
    try {
      for (let index = 0; index < CONDITIONS.paired_trials; index++) {
        for (const label of CONDITIONS.orders[index]) {
          const result = runTrial(label, index + 1, artifacts[label].path);
          assert.equal(result.artifact_sha256, artifacts[label].sha256, 'Artifact changed during the comparison');
          assert.deepEqual(result.fixtures, initialFixtures, 'Fixture or SDK changed during the comparison');
          report.trials.push(result);
          console.error(`pair ${index + 1} ${label}: ${result.measured_ms.toFixed(3)} ms, ${result.emulation_fps.toFixed(3)} FPS`);
        }
      }
      assert.deepEqual(fixtures().metadata, initialFixtures, 'Fixtures changed during the comparison');
      for (const artifact of Object.values(artifacts)) assert.equal(hash(readFileSync(artifact.path)), artifact.sha256);
      report.summary = summarize(report.trials);
    } catch (error) {
      report.error = error.stack || String(error);
      report.summary = { accept_candidate: false, selection: 'baseline', reason: 'Comparison incomplete or fixtures changed; do not claim a speedup.' };
      process.exitCode = 1;
    }
    const json = JSON.stringify(report, null, 2) + '\n';
    if (outputPath) writeFileSync(outputPath, json);
    process.stdout.write(json);
  }
}
