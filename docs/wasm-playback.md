# Existing ruby.wasm player

The player keeps the existing console UI, canvas size and keyboard mappings.
The **Performance** section has **Limit to 60 FPS** and **Mute** checkboxes for
changing playback while running. The local `./rubyboy.wasm` download and existing
`https://proxy.sacckey.dev/rubyboy.wasm` fallback remain unchanged. No Wasm binary
needs to be committed to Git.

Execution and audio use a worker and an AudioWorklet. The scheduler is separate
from the Ruby VM adapter so a future Spinel build can use the same scheduler
and transfer path.

## Packed Ruby sources

`rubyboy.wasm` contains the Ruby VM, Rubyboy Ruby sources and bundled ROMs.
The pack command embeds `./lib` at `/lib`, and the browser loads `/lib/executor`
directly from the Wasm. There is no separate source download or JSON mounting.
Repack and upload the Wasm after changing any emulator source; built-in ROMs
remain under `/lib/roms`.

## Build Ruby 4.0.7 and pack the emulator

The build pins the stable Ruby 4.0.7 source and verifies its SHA-256 before
extracting it. `ruby_wasm` and `js` are pinned to 2.10.1. The toolkit's `4.0`
alias currently points to Ruby 4.0.0; `exe/rubyboy-wasm` adds a versioned source
configuration so a build cannot silently reuse that older alias.

Install a host Ruby 4.0.7 and Node 24.4.0, then run from the repository root:

```sh
mise install ruby@4.0.7 node@24.4.0
mise exec ruby@4.0.7 -- gem install bundler -v 4.0.20 --no-document
BUNDLE_IGNORE_CONFIG=1 BUNDLE_ONLY=wasm mise exec ruby@4.0.7 -- bundle install
mise exec ruby@4.0.7 -- ruby exe/rubyboy-wasm build
mise exec ruby@4.0.7 -- ruby exe/rubyboy-wasm pack
```

The build downloads WASI SDK 24.0 and Binaryen 108 and compiles a native
build-time Ruby and the wasm32-wasi Ruby VM. It needs the platform's native
C/C++ build tools, `make`, `curl`, and `tar`. On macOS these come from Xcode
Command Line Tools (`xcode-select --install`). The first build can take several
minutes. Build products and caches stay in Git-ignored `build/` and `rubies/`.
The output is `docs/ruby-js.wasm` and then `docs/rubyboy.wasm`. By default,
`pack` uses the SDK's `llvm-objcopy --strip-debug` to remove DWARF custom sections.
Executable code, data and function names are retained. For C-level debugging,
use `ruby exe/rubyboy-wasm pack --keep-debug`. Keep both files
out of Git; upload the latter through the existing release/download workflow.
Deploy the updated SDK imports and new Wasm together so the JavaScript SDK and
the embedded `js` extension have matching versions.

YJIT and ZJIT are unavailable on wasm32-wasi. Enabling YJIT in the host Ruby
only affects build-time Ruby execution; it does not enable JIT inside the Wasm
VM. The target C compiler already uses `-O3 -fno-fast-math`, and the toolkit
applies Binaryen `-O3` during its Asyncify step. Further optimization needs a
measured comparison rather than assuming a higher optimization level is faster.

## Run

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

| URL | Execution | Sound |
| --- | --- | --- |
| `http://127.0.0.1:8765/` | Normal speed | Muted |
| `http://127.0.0.1:8765/?throttle=0&mute=1` | Unlimited | Muted |
| `http://127.0.0.1:8765/?throttle=1&mute=0` | Normal speed | Enabled after a key or button interaction |

Both checkboxes are checked by default; URL parameters override their initial
state. Uncheck **Limit to 60 FPS** for unlimited execution. Uncheck **Mute** to
start sound from that interaction, and check it to clear queued audio and
suspend playback. The current checkbox states are used even if they change
before the Ruby VM finishes loading.

Both modes advance CPU, timer, PPU and APU. Muting suppresses audio transfer and
playback after generating and consuming the APU samples; it does not skip APU
emulation. `mute=0` also permits audio in unlimited mode, but audio is generated
faster than real time, so that combination is not normal-speed playback.

Both modes execute and present one frame-step per worker task. Normal mode
paces tasks at `70,224 / 4,194,304` seconds per frame (about 59.73 FPS), including
emulation and buffer processing in that interval. It waits only when the frame
finishes early. If the core is slower, the next task runs without an additional
wait. A delayed timer or slow core does not accumulate a batch of hidden
catch-up frames; game time advances at the available processing speed.
Unlimited mode removes the deadline. LCD-disabled execution remains bounded by
one frame's CPU time so the worker can accept further input.

Completed 512-frame stereo APU blocks are packed as little-endian Float32.
The worklet holds at most 2,048 stereo frames and resamples 48 kHz input if the
device rate differs. ROM changes clear queued audio and reset the execution
clock. Keyboard mappings stay K→A, J→B, I→Start and U→Select.

## Verification

The JavaScript unit tests need Node:

```sh
node scripts/test_wasm_frontend.cjs
```

With the project's development gems installed, the Ruby adapter test and
repository lint check are:

```sh
ruby -S rspec -Ilib spec/rubyboy/emulator_wasm_spec.rb
ruby -S rubocop
```

The actual Ruby VM test also needs Ruby and the same JavaScript dependencies
used by the existing page. Install these under the Git-ignored build directory:

```sh
npm install --prefix build/browser-runtime --no-audit --no-fund \
  @ruby/wasm-wasi@2.10.1 @bjorn3/browser_wasi_shim@0.4.2
node scripts/verify_wasm_package.mjs /path/to/rubyboy.wasm
node scripts/test_wasm_runtime.mjs /path/to/rubyboy.wasm
```

If the Wasm is at `docs/rubyboy.wasm`, omit the path argument.
`verify_wasm_package.mjs` checks Ruby 4.0.7, the current Rubyboy version, and the
file list, size and SHA-256 of every regular file packed under `/lib`.
`test_wasm_runtime.mjs` prints the host Ruby description, Wasm Ruby description,
Wasm hash and ROM hash. It compares pixels and Float32 audio with CRuby for
frame execution, including input changes. It also checks source loading, copied
buffers, audio consumption, LCD-off behavior and the existing packed ROMs.

## Check an additional Wasm optimization

The following is a fixed experiment, not a claim that `-O4` is faster.
Prepare the candidate before running either artifact's benchmark:

```sh
mkdir -p build/wasm-rebuild
mise exec ruby@4.0.7 -- ruby exe/rubyboy-wasm pack --keep-debug
cp docs/rubyboy.wasm build/wasm-rebuild/rubyboy-ruby4.0.7-baseline.wasm
build/toolchain/binaryen/bin/wasm-opt \
  build/wasm-rebuild/rubyboy-ruby4.0.7-baseline.wasm \
  --strip-dwarf -O4 --converge -g \
  -o build/wasm-rebuild/rubyboy-ruby4.0.7-opt.wasm
mise exec ruby@4.0.7 node@24.4.0 -- node scripts/test_wasm_runtime.mjs \
  build/wasm-rebuild/rubyboy-ruby4.0.7-opt.wasm
mise exec node@24.4.0 -- node scripts/compare_wasm_optimization.mjs \
  build/wasm-rebuild/rubyboy-ruby4.0.7-baseline.wasm \
  build/wasm-rebuild/rubyboy-ruby4.0.7-opt.wasm \
  build/wasm-rebuild/ruby4.0.7-opt-comparison.json
mise exec ruby@4.0.7 -- ruby exe/rubyboy-wasm pack
```

Install the JavaScript dependencies from the Verification section first.
The benchmark runs five alternating pairs: baseline/candidate, candidate/baseline,
baseline/candidate, candidate/baseline, baseline/candidate. Every trial starts a
fresh Node process and Ruby VM, runs 300 warmup frame-step calls, then times
600 calls with all buttons released. It validates the same Ruby sources packed under `/lib` and uses the same Tobu ROM, keeps the APU active, and includes framebuffer/audio VFS
copies plus transfers of both buffers. SHA-256 calculation is outside timing.
Frame calls run in a synchronous loop; no scheduler, real-time synchronization,
60 FPS limiter, VSync, or audio-device backpressure is used.

This is a Node emulation-and-transfer measurement. It excludes Canvas drawing,
AudioWorklet playback, worker task scheduling and browser rendering. It is not
the browser's visible FPS counter or a Spinel comparison. Results cover this
fixed ROM segment and workload; they do not establish performance for all games.
Cold Wasm compilation and VM initialization are recorded separately from warmed
throughput, excluding network transfer and Node startup.

The selection rule was set before measurement: all ten trials must produce
identical final framebuffer, full measured Float32 stereo audio, and final
emulator state hashes; the candidate must be faster in every paired trial; and
its median paired FPS gain must be at least 5%. Otherwise retain the standard
artifact for throughput. The JSON retains every trial, input/source/artifact
hash, runtime identity and separate cold timings; do not drop slower trials.

## Measured result: 2026-10-04

These historical measurements used the former JSON source-loading path. The
current player and benchmark load packed `/lib` sources directly. The results
below are retained as a record of that earlier experiment; they are not new
measurements of the current startup path.

Environment: Apple M4 (10 logical CPUs), arm64, Darwin 24.5.0,
Node v24.4.0 / V8 13.6.233.10-node.17;
Ruby `4.0.7 (2026-09-15 revision 229531a6cf) +PRISM [wasm32-wasi]`;
YJIT and ZJIT disabled. Both artifacts use WASI SDK 24.0, compiler
`-O3 -fno-fast-math`, ruby.wasm/js/JavaScript SDK 2.10.1, shim 0.4.2 and
Binaryen 108. The benchmark script and selection conditions were prepared
before measuring either artifact. All compilation and optimizer jobs finished,
previous emulator test tabs were closed, and a fixed 30-second pause preceded
the sequential benchmark. Ordinary desktop activity was not controlled.

| Pair | Order | Baseline seconds | Candidate seconds | Baseline FPS | Candidate FPS | Paired FPS gain |
| --- | --- | ---: | ---: | ---: | ---: | ---: |
| 1 | baseline → candidate | 9.990348 | 9.929312 | 60.058 | 60.427 | 0.615% |
| 2 | candidate → baseline | 10.006520 | 9.947389 | 59.961 | 60.317 | 0.594% |
| 3 | baseline → candidate | 10.044488 | 9.910858 | 59.734 | 60.540 | 1.348% |
| 4 | candidate → baseline | 9.997161 | 9.889041 | 60.017 | 60.673 | 1.093% |
| 5 | baseline → candidate | 9.974955 | 9.877491 | 60.151 | 60.744 | 0.987% |

Median throughput: **60.017 → 60.540 FPS**.
The median paired FPS gain was **0.987%**. All five pairs favored
the candidate, but the predeclared 5% adoption condition was not met. Therefore
`-O4 --converge` is **not** added to the standard build. This is a small observed
difference in one workload, not evidence of a general emulator speedup.

Median first-process Wasm compile time was
14.134 ms → 11.764 ms;
median fresh-VM initialization/mount/ROM load time was
190.534 ms → 299.304 ms.
These are separate measurements and include no network transfer.

All ten trials agreed on 600 returned frame steps, 3,846,144 measured audio
bytes and final state. SHA-256 values:

- Framebuffer: `dc09d1947f18ca374ed04ae87beffa88c69a1fe8033bb086cb82af81365bd23d`
- Measured audio: `31c426285e369204dbc790059a7cc32669978ff7c7f0fd927834274638a82589`
- Final emulator Marshal state: `3fa7a02d1cb7aa113bf900ecee12cfb6e0a13bfd79a65e662ec3bf81781065ef`
- Source bundle: `af47e2bb696652526aec936af684c94d76c19d880ffddcdc881c9af1a9000fe3`
- Tobu ROM: `5d3871cae77db2287807e8914fd21f76203e73aa3fec20955489d45cb4571d8f`
- Benchmark script: `8b64c5fde26cf0042052b396461b0a602a856054b507927634683d6bd58bafd5`

| Artifact | Bytes | SHA-256 |
| --- | ---: | --- |
| Standard build with DWARF (benchmark baseline) | 53,755,170 | `9f4a788d975517a514a7002a6336fe1c0be0abaff2ce95ce7f9bfad1795d12cb` |
| Additional `-O4 --converge` candidate | 32,901,233 | `d312fcb234d85c8da3fab20c1c039eccc9e485091939ac2fa9ada49328cf8a6b` |
| Standard build after `llvm-objcopy --strip-debug` (distribution output) | 33,644,659 | `d5cce4e1ece27c23a34f9add63977ed7f1c8e230e8cf85d1b658a153c7930492` |

Distribution uses **debug information removal only**, a **37.41%** reduction
from the unstripped standard artifact. This was checked separately after the
throughput experiment: every non-custom Wasm section (including code and data)
remained byte-for-byte identical to the baseline; the `name`, `producers` and
`target_features` sections remain. No additional runtime optimization was
selected, and no FPS gain is claimed for this size reduction. Both the direct
package check and the CRuby pixel/audio comparison also passed for this final
artifact. Browser startup, gameplay input, live throttle/mute changes and
AudioWorklet loading were also checked with no reported browser errors; this
background-tab check was separate from the throughput measurement. Packing
includes exactly 57 regular files: 34 Ruby sources and 17 ROMs.

All trial records, fixture hashes and cold timings are retained locally at
`build/wasm-rebuild/ruby4.0.7-opt-comparison.json`. Running the commands above
regenerates the full report on another machine. Absolute paths and debug info
can vary between builds, so compare source/ROM hashes and actual runtime identity
rather than expecting an identical Wasm hash across machines.

## Browser and Spinel comparison conditions

For a browser or Spinel comparison, use identical Ruby source hashes, ROM bytes, input sequence,
frame counts, warmup, throttle/mute settings, browser/foreground state, Canvas
scaling, scheduler and transfer policy. Report the actual Ruby VM version and
Wasm/compiler identities as well.

The visible FPS counter retains its existing meaning: received/drawn images
in the last second. Each worker task now presents the frame-step it computes.
The display counter still measures message arrivals rather than a timed core benchmark. `pixelData.frameCount` and
`pixelData.completedFrames` separately report emulated frame counts. Use those
counts and elapsed time for processing throughput; do not infer a compiler
speedup from the visible counter. Recording adds work, so time benchmarks
separately from recordings.

Both modes count bounded frame-step calls, including an LCD-off CPU-time fallback.
Use the same mode and frame-count definition for both builds, especially with
ROMs that temporarily disable their LCD.

The Ruby VM adapter packs output through the WASI virtual filesystem. A future
Spinel adapter may expose linear-memory buffers directly. An end-to-end player
comparison includes that bridge cost; a claim about core compilation speed
also needs a separate measurement of the emulation core.
