# WebAssembly builds

Rubyboy runs in the browser in two builds that share the same web page and
JavaScript. Both run the same Ruby code: `lib/executor.rb` and
`Rubyboy::EmulatorWasm`.

| Build | URL | How the Ruby code runs | Wasm file |
| --- | --- | --- | --- |
| ruby.wasm | https://sacckey.github.io/rubyboy/ | CRuby compiled to WebAssembly, with the Rubyboy sources packed in | `docs/rubyboy.wasm` |
| Spinel | https://sacckey.github.io/rubyboy/spinel/ | Ruby compiled to C by Spinel, then to WebAssembly | `docs/spinel/rubyboy-spinel.wasm` |

## How it works

| File | Role |
| --- | --- |
| `docs/index.html`, `docs/index.js` | Page, keyboard and touch input, Canvas drawing, audio playback |
| `docs/worker.js`, `docs/spinel/worker.js` | Download the build's Wasm and create the adapter |
| `docs/emulation-worker.js` | Worker messages: start, input, ROM loading, playback options |
| `docs/emulation-loop.js` | Frame pacing |
| `docs/rubyboy-vm.js` | Calls the Ruby `Executor` and reads `/video.data` and `/audio.data` from the WASI file system |
| `docs/audio-worklet.js` | Audio buffering and resampling |
| `docs/spinel/rubyboy-spinel.mjs` | Puts the bundled files in the WASI file system and calls the Spinel build's exported functions |
| `wasm/spinel_main.rb` | Entry points that Spinel compiles from the existing `Executor` |
| `wasm/glue.c` | Exports those entry points to JavaScript and reports Ruby exceptions |

The worker runs one frame per task. With the 60 FPS limit, frames are paced at
70,224 / 4,194,304 seconds (about 59.73 FPS); a late or slow frame does not cause
catch-up frames. A game with the LCD turned off still returns after one frame of
CPU time.

The APU always runs. Its 48 kHz stereo samples are sent to an AudioWorklet that
buffers up to 2,048 frames, drops the oldest samples when full, and resamples if
the device rate differs. When muted, samples are generated but not sent.

## Run locally

```sh
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

Open http://127.0.0.1:8765/ (ruby.wasm) or http://127.0.0.1:8765/spinel/ (Spinel).
Each page loads its local Wasm file first. If that file is missing, it loads the
asset of the latest GitHub Release through `https://proxy.sacckey.dev/`, so the
pages work without building anything.

## Playback options

The **Limit to 60 FPS** and **Mute** checkboxes change playback while running.
By default the speed is unlimited, so the page shows how fast each build runs,
and the sound is muted. URL parameters set their initial state.

| URL | Speed | Sound |
| --- | --- | --- |
| `/` | Unlimited | Muted |
| `/?throttle=1` | 60 FPS | Muted |
| `/?throttle=1&mute=0` | 60 FPS | Starts at the first key press or click |

The **Runtime** section on each page names the build and links to the other one.

## ruby.wasm build

The build needs Ruby, a native C/C++ toolchain, `make`, `curl` and `tar`
(on macOS, the Xcode Command Line Tools). From the repository root:

```sh
BUNDLE_IGNORE_CONFIG=1 BUNDLE_ONLY=wasm bundle install
ruby wasm/rubyboy-wasm build
ruby wasm/rubyboy-wasm pack
```

- `build` compiles CRuby for WebAssembly into `docs/ruby-js.wasm`. The first run
  downloads the WASI SDK and Ruby sources and takes several minutes; caches stay
  in `build/` and `rubies/`. The Ruby version is ruby_wasm's `4.0` (Ruby 4.0.0).
- `pack` writes `docs/rubyboy.wasm` with the Git-tracked files under `lib/`
  mounted at `/lib`, and removes C debug information. Use `pack --keep-debug`
  to keep it. Run `pack` again after changing anything under `lib/`.
- The JavaScript SDK version in `docs/worker.js` (`@ruby/wasm-wasi@2.10.1`) must
  match the `js` gem in the Gemfile. Update both together.
- YJIT is not available inside the Wasm.

## Spinel build

The browser build uses upstream Spinel, built in `../spinel` as described in
[spinel/README.md](../spinel/README.md#build-spinel). It also needs Python 3,
[WASI SDK 34](https://github.com/WebAssembly/wasi-sdk/releases/tag/wasi-sdk-34)
or later, and a browser that supports WebAssembly exception handling.

```sh
python3 wasm/build.py --spinel-dir ../spinel --wasi-sdk /path/to/wasi-sdk-34
```

`build.py` builds Spinel's WebAssembly runtime, compiles `wasm/spinel_main.rb` to C
with callable entry points (`--ext-init` and `--ext-entry`), links it with
`wasm/glue.c` using the flags from `spinel --print-build`, and appends the
Git-tracked files in `lib/roms` as a `rubyboy-files` custom section.
`SPINEL_DIR` and `WASI_SDK` can be used instead of the options.

| Generated file | In Git | Contents |
| --- | --- | --- |
| `build/spinel-wasm/rubyboy.c`, `rubyboy.h` | No | Spinel's C output |
| `build/spinel-wasm/rubyboy-spinel.wasm` | No | Linked module without files |
| `docs/spinel/rubyboy-spinel.wasm` | No | The above with the Git-tracked files in `lib/roms` appended |
| `docs/spinel/index.html` | Yes | `docs/index.html` with asset paths and page description adjusted |

## Tests

The two Wasm tests load these packages from the Git-ignored `build/` directory:

```sh
npm install --prefix build/browser-runtime --no-save --no-audit --no-fund \
  @ruby/wasm-wasi@2.10.1 @bjorn3/browser_wasi_shim@0.4.2
```

| Command | Tests | Needs |
| --- | --- | --- |
| `node wasm/test/frontend.cjs` | Frame pacing, input latching, audio buffering | Nothing |
| `bundle exec rspec spec/rubyboy/emulator_wasm_spec.rb` | `EmulatorWasm` and `Executor` in CRuby | Nothing |
| `node wasm/test/ruby_wasm.mjs` | Packed `/lib` files match Git, ROM loading and frames in ruby.wasm | `pack`, the packages above |
| `node --experimental-wasm-exnref wasm/test/spinel.mjs` | Spinel output matches CRuby, embedded files match Git, ROM loading | Spinel build, the packages above, `ruby` on `PATH` |

## Deploy

GitHub Pages serves `docs/` from `main`. The Wasm files are not in Git, so the
published pages load them from the proxy, which serves the latest GitHub
Release's assets.

1. Commit changes to `docs/`, including a regenerated `docs/spinel/index.html`.
   If `wasm/glue.c` or `docs/spinel/rubyboy-spinel.mjs` changed, do steps 2 and 3
   right after the change reaches `main`; the page and the Wasm must match.
2. Upload the Wasm files to the latest release:

   ```sh
   gh release upload "$(gh release view --json tagName -q .tagName)" \
     docs/rubyboy.wasm docs/spinel/rubyboy-spinel.wasm --clobber
   ```

3. Purge the proxy cache for `/rubyboy.wasm` and `/rubyboy-spinel.wasm`.
   Otherwise it keeps serving the old files for up to four hours.
