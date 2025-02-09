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
  class EmulatorHeadless
    def initialize(rom_path)
      rom_data = File.open(rom_path, 'r') { _1.read.bytes }
      rom = Rom.new(rom_data)
      ram = Ram.new
      mbc = Cartridge::Factory.create(rom, ram)
      interrupt = Interrupt.new
      @ppu = Ppu.new(interrupt)
      @timer = Timer.new(interrupt)
      joypad = Joypad.new(interrupt)
      @apu = Apu.new
      bus = Bus.new(@ppu, rom, ram, mbc, @timer, interrupt, joypad, @apu)
      @cpu = Cpu.new(bus, interrupt)
    end

    def step
      loop do
        cycles = @cpu.exec
        @timer.step(cycles)
        @apu.step(cycles)
        break if @ppu.step(cycles)
      end
    end
  end
end
