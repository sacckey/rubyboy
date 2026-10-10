<br>
<p align="center">
  <img src="/resource/logo/logo.svg" width="480px">
</p>
<br>

A Game Boy emulator written in Ruby

**Try it in your browser:**
[ruby.wasm version](https://sacckey.github.io/rubyboy/) (CRuby compiled to WebAssembly) /
[Spinel version](https://sacckey.github.io/rubyboy/spinel/) (the same Ruby code compiled to C by Spinel, then to WebAssembly)

## Screenshots
<div align="center">
  <img src="/resource/screenshots/pokemon.png" width="400px"/>
  <img src="/resource/screenshots/puyopuyo.png" width="400px"/>
</div>

## Installation

Rubyboy requires Ruby 4.0 or higher and [SDL2](https://wiki.libsdl.org/SDL2/Installation).

    $ gem install rubyboy

> [!TIP]
> Run with YJIT (`RUBYOPT=--yjit`) for better performance.

## Usage

    $ RUBYOPT=--yjit rubyboy [rom_path]

Without a ROM path, it runs the bundled [Tobu Tobu Girl](https://tangramgames.dk/tobutobugirl/).

### Controls

| Key | Button |
| :---: | :---: |
| `W` `A` `S` `D` | ↑ ← ↓ → |
| `K` | A |
| `J` | B |
| `U` | Select |
| `I` | Start |
| `1`–`0` | Save state to slot 1–9, 0 |
| Left `Shift` + `1`–`0` | Load state from that slot |

Battery-backed games save to `<rom>.sav`, and save states go to `<rom>.state<N>`,
next to the ROM file.

### Options

| Option | Effect |
| --- | --- |
| `--frames N` | Exit after N frames |
| `--unlimited` | Run as fast as possible; audio that cannot be played in time is dropped |

## Benchmark

On an Apple M4, Rubyboy runs at about 110 FPS on CRuby, 290 FPS with YJIT and
800 FPS when compiled with Spinel. See [BENCHMARK.md](BENCHMARK.md) for the method and details.

## Other ways to run

- [WebAssembly builds](wasm/README.md): the browser versions (ruby.wasm and Spinel)
- [Spinel](spinel/README.md): compile Rubyboy to a native executable

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/sacckey/rubyboy. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
