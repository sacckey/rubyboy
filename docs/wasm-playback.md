# Existing ruby.wasm player

The player keeps the existing console UI, canvas size and keyboard mappings.
The **Performance** section has **Limit to 60 FPS** and **Mute** checkboxes for
changing playback while running. The local `./rubyboy.wasm` download and existing
`https://proxy.sacckey.dev/rubyboy.wasm` fallback remain unchanged. No Wasm binary
needs to be committed to Git.

Execution and audio use a worker and an AudioWorklet. The scheduler is separate
from the Ruby VM adapter so a future Spinel build can use the same scheduler
and transfer path.

## Source bundle

The downloaded Wasm includes a Ruby VM and packed Ruby files. Those packed
files can be older than the repository. `scripts/build-browser-core.rb`
collects the current browser core's `require_relative` dependency graph into
`docs/rubyboy-core.json`. This is about 89 KB of text, including a SHA-256 for
each Ruby source; it contains no Ruby VM, SDL dependencies or ROM binaries.

The worker mounts these files at `/rubyboy-core/lib` and loads the executor
from that exact location. The unique path avoids the packed `/lib` mount taking
precedence. Built-in ROMs continue to come from the existing `/lib/roms`.
Uploaded ROMs use the same CPU, timer, PPU and APU code.

Regenerate and commit the JSON whenever one of its source files changes:

```sh
ruby scripts/build-browser-core.rb
```

The generator needs only Ruby's standard library. The runtime test checks that
every bundled file and its SHA-256 match the current repository. The worker
also validates the bundle's hashes before loading the Ruby sources.

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

Normal mode schedules against 4,194,304 T-cycles per second, with at most 250 ms
of catch-up per task. Each budget is at most 32,768 T-cycles (8,192 M-cycles).
CPU instructions cannot be split, so the Ruby adapter
carries instruction overshoot into the next budget. Unlimited mode executes
one frame per task. LCD-disabled execution returns after one frame's CPU time
so the worker can accept further input.

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
  @ruby/wasm-wasi@2.7.1 @bjorn3/browser_wasi_shim@0.3.0
node scripts/test_wasm_runtime.mjs /path/to/rubyboy.wasm
```

If the Wasm is at `docs/rubyboy.wasm`, omit the path argument. The test prints
the host Ruby description, Wasm Ruby description, Wasm hash, Ruby source bundle
hash and ROM hash. It compares pixels and Float32 audio with CRuby for both
frame execution and split cycle budgets, including input changes. It also
checks source loading, copied buffers, audio consumption, instruction overshoot,
LCD-off behavior and the existing packed ROMs.

The validated environment used host Ruby 4.0.7, Node 24.4.0 and the existing
v1.5.1 Wasm asset, which contains Ruby 3.4.1. Its SHA-256 is
`bfb48154e1e3b3d2636adf483935d37852ca80603cdeff56d4f54c4b91071440`.
The emulator sources came from the current JSON bundle, not v1.5.1's embedded
emulator. At validation time, the proxy was returning the missing v1.6.0 asset's
HTML error page; the download configuration was left unchanged.

## Comparison conditions

This change prepares the existing player; it is not a benchmark result.
For a comparison, use identical Ruby source hashes, ROM bytes, input sequence,
frame counts, warmup, throttle/mute settings, browser/foreground state, Canvas
scaling, scheduler and transfer policy. Report the actual Ruby VM version and
Wasm/compiler identities as well.

The visible FPS counter retains its existing meaning: received/drawn images
in the last second. Catch-up can process several frames and send only the last
image, so this counter is not processing FPS. `pixelData.frameCount` and
`pixelData.completedFrames` separately report emulated frame counts. Use those
counts and elapsed time for processing throughput; do not infer a compiler
speedup from the visible counter. Recording adds work, so time benchmarks
separately from recordings.

In normal mode the processing counter counts completed PPU frames. Unlimited
mode counts bounded frame-step calls, including an LCD-off CPU-time fallback.
Use the same mode and frame-count definition for both builds, especially with
ROMs that temporarily disable their LCD.

The Ruby VM adapter packs output through the WASI virtual filesystem. A future
Spinel adapter may expose linear-memory buffers directly. An end-to-end player
comparison includes that bridge cost; a claim about core compilation speed
also needs a separate measurement of the emulation core.
