## [Unreleased]

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
