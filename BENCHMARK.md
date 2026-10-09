# Benchmarks

## Choosing a method

| Runtime | Method |
| --- | --- |
| CRuby (with or without YJIT) | [`rubyboy-bench`](#cruby) |
| Spinel, native executable | [`rubyboy-bench` compiled with Spinel](#spinel) |
| ruby.wasm, Spinel WebAssembly | Not available. The FPS counter on the web page shows drawn frames per second and is not a benchmark. |

## CRuby

From the repository root:

```sh
bundle exec ruby --yjit -Ilib exe/rubyboy-bench \
  --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5
```

| Option | Default | Meaning |
| --- | --- | --- |
| `--rom-path PATH` | `lib/roms/tobu.gb` | ROM to run |
| `--frames N` | 1500 | Measured frames per trial |
| `--warmup-frames N` | 0 | Unmeasured frames before each trial |
| `--count N` | 3 | Number of trials |

Each trial starts with a fresh emulator and runs the CPU, timer, PPU and APU
without input, saves, drawing, audio output or real-time synchronization.
The command prints each trial's duration and the aggregate FPS (total measured
frames divided by total measured time).

## Spinel

Build `rubyboy-bench` with Spinel as described in
[spinel/README.md](spinel/README.md#benchmark), then run it with the same options:

```sh
build/spinel/rubyboy-bench \
  --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5
```

The executable prints `Ruby: 4.0.7`, which is the Ruby version Spinel reports,
not a CRuby version. Record `spinel --version` instead.

## Comparing results

Use the same machine, ROM, `--frames`, `--warmup-frames` and `--count` for every
runtime. Use a warmup so that YJIT has compiled the hot code before measurement.
Record the Ruby version (`ruby -v`) or Spinel revision (`spinel --version`) and the
Rubyboy revision with each result.
