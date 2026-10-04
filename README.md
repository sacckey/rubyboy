<br>
<p align="center">
  <img src="/resource/logo/logo.svg" width="480px">
</p>
<br>

A Game Boy emulator written in Ruby

**[Try the demo in your browser!](https://sacckey.github.io/rubyboy/)** - Powered by WebAssembly

## Screenshots
<div align="center">
  <img src="/resource/screenshots/pokemon.png" width="400px"/>
  <img src="/resource/screenshots/puyopuyo.png" width="400px"/>
</div>

## Requirements
[SDL2](https://wiki.libsdl.org/SDL2/Installation) 2.0.18 or higher.

## Installation

This project requires Ruby 3.2.0 or higher.

> [!TIP]
> To enhance performance, it is highly recommended to use Ruby 3.3.x with YJIT.

Install the gem and add to the application's Gemfile by executing:

    $ bundle add rubyboy

If bundler is not being used to manage dependencies, install the gem by executing:

    $ gem install ffi rubyboy

## Usage

    $ RUBYOPT=--yjit rubyboy <rom_path>

| Key   | Button |
| :---: | :----: |
| `W`   | ↑      |
| `A`   | ←      |
| `S`   | ↓      |
| `D`   | →      |
| `J`   | A      |
| `K`   | B      |
| `U`   | Select |
| `I`   | Start  |

## Bounded execution

The player accepts `--frames N` to stop after N completed frames, `--no-audio`
to disable audio output while continuing APU emulation, and `--unlimited` to
disable real-time synchronization:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy --frames 600 --unlimited --no-audio lib/roms/tobu.gb
```

Normal playback remains synchronized to real time with audio enabled.
`--unlimited` alone still permits audio queue backpressure; use `--no-audio`
for maximum speed. These player options retain keyboard input and battery save
loading/writing. Use the benchmark below for comparisons with a fixed start state.

## Benchmarking

Run a headless benchmark with an explicit warmup before each measured trial:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy-bench \
  --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5 --json
```

Add `--render` to include SDL drawing, with audio output and VSync disabled.
No environment variable is required; the benchmark overrides the VSync setting
for its renderer, including `SDL_RENDER_VSYNC=1`:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy-bench \
  --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5 --render --json
```

Both modes run the same CPU, timer, PPU and APU frame processing. Each trial
starts with a fresh emulator, ignores battery saves, accepts no game input and
runs without real-time synchronization or audio output. Initialization, warmup
and display cleanup are excluded from the measured duration. Warmup advances
the machine state by the requested number of frames in both modes. The defaults
are 3 trials, 1500 measured frames and no warmup; counts and measured frames must
be positive, and warmup frames may be zero.

Without `--json`, the command prints each trial's duration and aggregate FPS.
With `--json`, stdout contains one JSON document with individual durations/FPS,
aggregate FPS, runtime identity and execution conditions. Aggregate FPS is the
total measured frame count divided by the sum of measured durations. Closing
the window before a trial finishes aborts the benchmark with a nonzero exit
status instead of reporting a result for that incomplete trial.

For comparisons, use the same source revision, ROM, frame counts, warmup,
window/display settings and SDL render driver. Normal playback retains its
existing VSync setting. Rendered FPS measures frame
processing and SDL drawing calls; it does not count distinct frames visible on
the monitor. Measure performance without recording, then use a separate
`--render --count 1` run for a reference recording. Preserve elapsed real time
when converting the recording to GIF so that speed differences remain visible.

## Browser playback (ruby.wasm)

The existing browser UI uses a worker for emulation and an AudioWorklet for
sound. Use the **Limit to 60 FPS** and **Mute** checkboxes in **Performance** to
change playback while running. Both are checked by default. URL parameters set
their initial state: `?throttle=0&mute=1` for unlimited, muted playback, or
`?throttle=1&mute=0` for normal playback with sound after the first interaction.
The APU continues to run in all modes.

The large Wasm download remains local-first with the existing proxy fallback;
Wasm files remain excluded from Git. A generated text bundle supplies the
current Ruby sources separately, so an older downloaded module cannot silently
provide an older emulator implementation. Regenerate it after changing browser
core code:

```sh
ruby scripts/build-browser-core.rb
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

See [browser playback and verification](docs/wasm-playback.md) for the source
bundle, verification commands and comparison conditions.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sacckey/rubyboy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/sacckey/rubyboy/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rubyboy project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/sacckey/rubyboy/blob/main/CODE_OF_CONDUCT.md).
