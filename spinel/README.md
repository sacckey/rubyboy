# Spinel

[Spinel](https://github.com/matz/spinel) compiles Ruby to C. The existing
`exe/rubyboy` and `exe/rubyboy-bench` compile without changes into native
executables, so Rubyboy can be played and benchmarked without CRuby.
For the browser version built with Spinel, see [wasm/README.md](../wasm/README.md#spinel-build).

## Build Spinel

Spinel needs a C compiler, `make` and Ruby to build. These commands put it in
`../spinel`, next to this repository:

```sh
git clone https://github.com/matz/spinel.git ../spinel
make -C ../spinel deps
make -C ../spinel
```

## Play

From the repository root:

```sh
mkdir -p build/spinel
../spinel/bin/spinel -I lib exe/rubyboy -o build/spinel/rubyboy
build/spinel/rubyboy lib/roms/tobu.gb
```

The executable uses SDL2 like the gem, and accepts the same keys and options
(see [README.md](../README.md#usage)).

## Benchmark

```sh
mkdir -p build/spinel
../spinel/bin/spinel -I lib exe/rubyboy-bench -o build/spinel/rubyboy-bench
build/spinel/rubyboy-bench --rom-path lib/roms/tobu.gb --frames 1500 --warmup-frames 1500 --count 5
```

See [BENCHMARK.md](../BENCHMARK.md) for the options and how to compare runtimes.

## Verified with

Spinel `7d999f50c` (matz/spinel, 2026-10-10) on macOS (Apple Silicon).
