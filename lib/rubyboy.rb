# frozen_string_literal: true

require 'benchmark'
require_relative 'rubyboy/version'
require_relative 'rubyboy/bus'
require_relative 'rubyboy/cpu'
require_relative 'rubyboy/ppu'
require_relative 'rubyboy/rom'
require_relative 'rubyboy/timer'
require_relative 'rubyboy/lcd'

module Rubyboy
  class Console
    def initialize(rom_data)
      rom = Rom.new(rom_data)
      interrupt = Interrupt.new
      @ppu = Ppu.new
      @timer = Timer.new(interrupt)
      @bus = Bus.new(@ppu, rom, @timer, interrupt)
      @cpu = Cpu.new(@bus)
      @lcd = Lcd.new
    end

    def start
      until @lcd.window_should_close?
        cycles = @cpu.exec
        @timer.step(cycles)
        draw if @ppu.step(cycles)
      end
      @lcd.close_window
    rescue StandardError => e
      p e.to_s[0, 100]
      raise e
    end

    def draw
      pixel_data = buffer_to_pixel_data(@ppu.buffer)
      @lcd.draw(pixel_data)
    end

    def buffer_to_pixel_data(buffer)
      buffer.map do |row|
        [row, row, row]
      end.flatten.pack('C*')
    end
  end
end

rom_data = File.open(File.expand_path('roms/cpu_instrs/cpu_instrs.gb', __dir__), 'r') { _1.read.bytes }
Rubyboy::Console.new(rom_data).start
