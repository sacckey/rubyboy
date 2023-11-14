# frozen_string_literal: true

require 'gosu'
require 'benchmark'
require_relative 'rubyboy/version'
require_relative 'rubyboy/bus'
require_relative 'rubyboy/cpu'
require_relative 'rubyboy/ppu'
require_relative 'rubyboy/rom'
require_relative 'rubyboy/timer'

module Rubyboy
  class Console < Gosu::Window
    SCALE = 4

    def initialize(rom_data)
      super(160 * SCALE, 144 * SCALE, false)
      # TODO: Display title
      self.caption = 'RUBY BOY'
      @total_cycles = 0

      rom = Rom.new(rom_data)
      interrupt = Interrupt.new
      @ppu = Ppu.new
      @timer = Timer.new(interrupt)
      @bus = Bus.new(@ppu, rom, @timer, interrupt)
      @cpu = Cpu.new(@bus)
    end

    def update
      while @total_cycles < 70224
        cycles = @cpu.exec
        @total_cycles += cycles
        @timer.step(cycles)
        @ppu.step(cycles)
      end
      @total_cycles -= 70224
    rescue StandardError => e
      p e.to_s[0, 100]
      raise e
    end

    def draw
      pixel_data = @ppu.draw_bg.flatten.pack('C*')
      @image = Gosu::Image.from_blob(160, 144, pixel_data)
      @image.draw(0, 0, 0, SCALE, SCALE)
    end

    def draw_pixel(x, y, color)
      x *= SCALE
      y *= SCALE
      c = Gosu::Color.new(255, color[0], color[1], color[2])
      draw_quad(x, y, c, x + SCALE, y, c, x, y + SCALE, c, x + SCALE, y + SCALE, c)
    end
  end
end

rom_data = File.open(File.expand_path('roms/cpu_instrs/cpu_instrs.gb', __dir__), 'r') { _1.read.bytes }
Rubyboy::Console.new(rom_data).show
