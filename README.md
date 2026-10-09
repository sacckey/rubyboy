<br>
<p align="center">
  <img src="/resource/logo/logo.svg" width="480px">
</p>
<br>

A Game Boy emulator written in Ruby

**[Try the demo in your browser!](https://sacckey.github.io/rubyboy/)** - Powered by WebAssembly

The [Spinel version](https://sacckey.github.io/rubyboy/spinel/) uses the same UI
with Ruby compiled to C and then to WebAssembly, without `ruby.wasm`.
See [build instructions](wasm/README.md).

## Screenshots
<div align="center">
  <img src="/resource/screenshots/pokemon.png" width="400px"/>
  <img src="/resource/screenshots/puyopuyo.png" width="400px"/>
</div>

## Requirements
[SDL2](https://wiki.libsdl.org/SDL2/Installation)

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

The player accepts `--frames N` to stop after N completed frames and
`--unlimited` to disable real-time synchronization. In unlimited mode, audio
that the device cannot play in time is dropped instead of slowing emulation:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy --frames 600 --unlimited lib/roms/tobu.gb
```

## Benchmarking

Run a headless benchmark with an explicit warmup before each measured trial:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy-bench \
  --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5
```

Each trial starts with a fresh emulator and runs the CPU, timer, PPU and APU
without input, saves, drawing, audio output or real-time synchronization.
Warmup is excluded from the measured duration. The defaults are 3 trials,
1500 measured frames and no warmup. The command prints each trial's duration
and the aggregate FPS (total measured frames divided by total measured time).

## Browser playback (ruby.wasm)

The existing browser UI uses a worker for emulation and an AudioWorklet for
sound. Use the **Limit to 60 FPS** and **Mute** checkboxes in **Performance** to
change playback while running. Both are checked by default. URL parameters set
their initial state: `?throttle=0&mute=1` for unlimited, muted playback, or
`?throttle=1&mute=0` for normal playback with sound after the first interaction.
The APU continues to run in all modes.

The large Wasm download remains local-first with the existing proxy fallback;
Wasm files remain excluded from Git. The Ruby VM, Rubyboy sources and ROMs are
packed into one Wasm file. Repack and upload `rubyboy.wasm` after changing the
emulator code.

```sh
mise exec ruby@4.0.7 -- ruby exe/rubyboy-wasm pack
python3 -m http.server 8765 --bind 127.0.0.1 --directory docs
```

See [browser playback and verification](docs/wasm-playback.md) for the build,
verification commands and comparison conditions.

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sacckey/rubyboy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/sacckey/rubyboy/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the Rubyboy project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/sacckey/rubyboy/blob/main/CODE_OF_CONDUCT.md).
