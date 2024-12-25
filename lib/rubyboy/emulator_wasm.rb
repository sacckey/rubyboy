# frozen_string_literal: true

require_relative 'apu'
require_relative 'bus'
require_relative 'cpu'
require_relative 'emulator'
require_relative 'ppu'
require_relative 'rom'
require_relative 'ram'
require_relative 'timer'
require_relative 'joypad'
require_relative 'interrupt'
require_relative 'cartridge/factory'

module Rubyboy
  class EmulatorWasm
    CPU_CLOCK_HZ = 4_194_304
    CYCLE_NANOSEC = 1_000_000_000 / CPU_CLOCK_HZ

    def initialize(rom_data)
      rom = Rom.new(rom_data)
      ram = Ram.new
      mbc = Cartridge::Factory.create(rom, ram)
      interrupt = Interrupt.new
      @ppu = Ppu.new(interrupt)
      @timer = Timer.new(interrupt)
      @joypad = Joypad.new(interrupt)
      @apu = Apu.new
      @bus = Bus.new(@ppu, rom, ram, mbc, @timer, interrupt, @joypad, @apu)
      @cpu = Cpu.new(@bus, interrupt)
    end

    def step(direction_key, action_key)
      @joypad.direction_button(direction_key)
      @joypad.action_button(action_key)
      loop do
        cycles = @cpu.exec
        @timer.step(cycles)
        return @ppu.buffer if @ppu.step(cycles)
      end
    end
  end
end
