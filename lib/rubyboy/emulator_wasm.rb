# frozen_string_literal: true

require_relative 'apu'
require_relative 'bus'
require_relative 'cpu'
require_relative 'ppu'
require_relative 'rom'
require_relative 'ram'
require_relative 'timer'
require_relative 'joypad'
require_relative 'interrupt'
require_relative 'cartridge/factory'

module Rubyboy
  class EmulatorWasm
    FRAME_CYCLES = 70_224

    attr_reader :audio_samples

    def initialize(rom_data)
      rom = Rom.new(rom_data)
      ram = Ram.new(rom)
      mbc = Cartridge::Factory.create(rom, ram)
      interrupt = Interrupt.new
      @ppu = Ppu.new(interrupt)
      @timer = Timer.new(interrupt)
      @joypad = Joypad.new(interrupt)
      @apu = Apu.new
      @bus = Bus.new(@ppu, rom, ram, mbc, @timer, interrupt, @joypad, @apu)
      @cpu = Cpu.new(@bus, interrupt)
      @audio_samples = []
    end

    def step(direction_key, action_key)
      set_input(direction_key, action_key)
      @audio_samples.clear
      elapsed_cycles = 0
      # LCD-off games must return to the browser event loop as well.
      while elapsed_cycles < FRAME_CYCLES
        cycles = @cpu.exec
        elapsed_cycles += cycles
        @timer.step(cycles)
        collect_audio(cycles)
        break if @ppu.step(cycles)
      end
      framebuffer
    end

    def framebuffer
      @ppu.buffer
    end

    private

    def set_input(direction_key, action_key)
      @joypad.direction_button(direction_key & 15)
      @joypad.action_button(action_key & 15)
    end

    def collect_audio(cycles)
      # Complete 512-frame stereo blocks are copied before the APU reuses its
      # sample buffer. Its incomplete block remains intact between calls.
      @audio_samples.concat(@apu.samples) if @apu.step(cycles)
    end
  end
end
