## [Unreleased]

- Require Ruby 4.0 or higher
- Keep audio output with --unlimited by dropping audio that cannot be played in time
- Remove the --no-audio player option
- Remove rubyboy-bench --render and --json, and the SDL 2.0.18 requirement
- Run the bundled Tobu Tobu Girl ROM when rubyboy or rubyboy-bench gets no ROM path, from any directory
- Read ROM files in binary mode, which fixes loading them on Windows
- Make the APU duty tables shareable between Ractors
- Ship only the runtime code, the default ROM and documents in the gem, without the rubyboy-wasm command or test ROMs

## [1.6.0] - 2026-10-04

- Add battery-backed saves and hardware-oriented save states
- Fix MBC1 ROM bank mapping, external RAM size and RAM banking
- Fix audio drop-outs and APU sample-rate drift
- Support Spinel compilation and fix SDL event allocation
- Add --frames, --unlimited and --no-audio player options
- Add benchmark warmup, SDL rendering and JSON output
- Disable VSync for rendered benchmarks and require SDL 2.0.18 or higher
- Update JSON and development dependencies for recent Ruby versions

## [1.5.1] - 2025-02-16

- Optimize Cartridge::Mbc1 and Bus

## [1.5.0] - 2025-02-09

- Add EmulatorHeadless and use it for bench
- Bump ruby.wasm version to 2.7.1

## [1.4.2] - 2025-01-11

- Use DefaultRubyVM
- Bump ruby.wasm version to 2.7.0

## [1.4.1] - 2024-12-25

- PPU performance optimization through data caching and pixel format changes

## [1.4.0] - 2024-09-29

- Works on browser using ruby.wasm

## [1.3.2] - 2024-05-04

- Revert "Enable YJIT when initialize"
- Add rubyboy-bench command
- Refactor Console class to use Emulator class
- Add option parsing and update default ROM path

## [1.3.1] - 2024-03-17

- Enable YJIT when initialize
- Down volume
- Update README.md
- Clear queued audio if buffer is full
- Add CPU clock and cycle timing

## [1.3.0] - 2024-03-09

- Add ffi to dependencies
- Add SDL2 wrapper
- Add audio
- Optimize cpu
- Cache R/W methods

## [1.2.0] - 2024-01-09

- Add logo
- Bump raylib-bindings version to 0.6.0
- Optimizing
- Remove unnecessary classes

## [1.1.0] - 2023-12-28

- Add bench option
- Improve speed by refactoring

## [1.0.0] - 2023-12-04

- Fix halt and timer
- Add executable command
- Refactoring
- tobu.gb works at 30fps

## [0.4.0] - 2023-11-20

- Fix interrupt
- Fix sprite priority
- Implement joypad
- Pass bgbtest

## [0.3.0] - 2023-11-19

- Fix bg rendering
- Add render_window
- Add render_sprites
- Add interrupt in ppu
- Add oam_dma_transfer
- Use raylib for rendering
- Pass dmg-acid2 test

## [0.2.0] - 2023-11-14

- Add MBC1
- Add interrupt and timer
- Add r/w address
- Add cpu instructions
- Update draw method
- Update ruby version
- Pass cpu_instrs and instr_timing tests

## [0.1.0] - 2023-10-12

- Initial release
- Only hello-world.gb will work
