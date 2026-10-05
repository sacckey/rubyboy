# Spinel WebAssembly build

This version compiles the existing `lib/executor.rb` and `Rubyboy::EmulatorWasm`
through **Ruby → Spinel-generated C → WebAssembly**. CPU, PPU, APU, cartridge
logic, framebuffer `pack('V*')`, audio `pack('e*')` and `File.binwrite` are the
same Ruby code used by the normal packed CRuby version. There is no handwritten
Rubyboy C implementation or Spinel-specific emulator class.

`wasm/spinel_main.rb` only declares callable entry points over the existing
Executor. Spinel generates their browser ABI with `--ext wasm`; its generic
JavaScript host supplies WASI and virtual files without emulator-specific
knowledge. Its host source is maintained in Spinel and copied during the build.

Both versions use the same `docs/rubyboy-vm.js`, emulation worker and scheduler,
UI, Canvas rendering and AudioWorklet. The shared adapter accepts a callable
Executor and a value converter: CRuby calls its Ruby object, while Spinel calls
compiled entry points. Both read the same `/video.data` and `/audio.data` files,
copy transferable buffers, and retain APU generation and Float32 packing when
muted. The normal version keeps its local-first download and proxy fallback.

## Build and run

Use a Spinel checkout containing the `--ext wasm` browser support added with
this change, Python 3, Make, a native C compiler, and WASI SDK 34 or later.
`bundle install`, SDL and Emscripten are not required for the Spinel build.
From Rubyboy, with Spinel in `../spinel` and the SDK already installed:

```sh
make -C ../spinel deps
python3 wasm/build.py --spinel-dir ../spinel --wasi-sdk /path/to/wasi-sdk-34
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

Open **http://127.0.0.1:8765/spinel/**. Under GitHub Pages the path is
`/rubyboy/spinel/`. The root page continues to use packed `rubyboy.wasm`.
The Spinel worker first tries local `./rubyboy-spinel.wasm`, then falls back to
`https://proxy.sacckey.dev/rubyboy-spinel.wasm` when the local response fails.
To use the proxy, upload the packed `rubyboy-spinel.wasm` as a GitHub Release
asset alongside the normal `rubyboy.wasm`.
`?throttle=0&mute=1` starts either version in unlimited, muted mode.

WASI SDK archives are available from the official
[wasi-sdk 34 release](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-34).
Pass the extracted host-specific directory to `--wasi-sdk`; `WASI_SDK` and
`SPINEL_DIR` can supply defaults. The build prints its commands and rebuilds
the target runtime to avoid reusing objects from another SDK or optimization
level. A browser supporting standardized Wasm exception handling is required.

## Generated assets

- `build/spinel-wasm/rubyboy-spinel.wasm`: compiled Executor and generic host ABI.
- `docs/spinel/rubyboy-spinel.wasm`: that module with the original `lib/roms` files
  embedded by Spinel's generic `scripts/wasm-pack.py`.
- `docs/spinel/spinel-vm.mjs`: an unmodified copy of Spinel's generic host.
- `docs/spinel/index.html`: generated from the existing root HTML with relative
  asset paths adjusted; the visible UI is shared.
- `docs/spinel/build-info.json`: compiler identities and source/artifact hashes.

These outputs are ignored by Git. ROMs are mounted read-only from the Wasm's
file section: no deployed ROM copies or separate ROM downloads are needed.
Deploy the whole `docs/` tree including generated assets. Rebuild when root HTML
or Spinel changes. The host uses the same pinned `browser_wasi_shim` 0.4.2 CDN
module as the normal version. Retain the full source changes when reproducing
an uncommitted build; a base Git revision alone does not identify those changes.

## Verification

For the normal runtime test, first build and pack `docs/rubyboy.wasm` from the
current sources using the [normal build instructions](../docs/wasm-playback.md).
For local tests, install the same browser dependencies into an ignored directory:

```sh
npm install --prefix build/browser-runtime --no-save \
  @ruby/wasm-wasi@2.10.1 @bjorn3/browser_wasi_shim@0.4.2
node scripts/test_wasm_frontend.cjs
node --experimental-wasm-exnref wasm/test.mjs
node scripts/test_wasm_runtime.mjs
```

The tests use Ruby from `PATH`; validation used Ruby 4.0.7 and Node 24.4.0.
`wasm/test.mjs` executes the actual Spinel module through the same RubyboyVM
adapter. Frame and cycle-budget scenarios use the existing CRuby reference;
framebuffer and Float32 audio bytes must match at six checkpoints in each
scenario. It also checks embedded files, uploads, ROM switching, exception
recovery, transfer copies, LCD-off return and 1500 continuous frames.

Spinel's separate generic host tests use a small Ruby program with no emulator
code, covering ordinary values, binary and text Strings, GC, exceptions and
virtual file operations. These demonstrate that the browser connection is
reusable independently of Rubyboy. This change does not include benchmark
results or claim an end-to-end speedup from playback FPS alone.
