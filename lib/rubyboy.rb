# frozen_string_literal: true

require 'gosu'
require_relative "rubyboy/version"
require_relative 'rubyboy/bus'
require_relative 'rubyboy/cpu'
require_relative 'rubyboy/ppu'
require_relative 'rubyboy/rom'

module Rubyboy
  class Console < Gosu::Window
    SCALE = 4

    def initialize(rom_data)
      super(160 * SCALE, 144 * SCALE, false)
      # TODO: Display title
      self.caption = 'RUBY BOY'
      @total_cycles = 0

      rom = Rom.new(rom_data)
      @ppu = Ppu.new
      @bus = Bus.new(@ppu, rom)
      @cpu = Cpu.new(@bus)
    end

    def update
      while @total_cycles < 70224
        cycles = @cpu.exec
        @total_cycles += cycles
        @ppu.step(cycles)
      end
      @total_cycles -= 70224

    rescue => e
      p e
    end

    def draw
      bg = @ppu.draw_bg
      bg.each_with_index do |xarray, i|
        xarray.each_with_index do |c, j|
          draw_pixel(j, i, c)
        end
      end
    end

    def draw_pixel(x, y, color)
      x *= SCALE
      y *= SCALE
      c = Gosu::Color.new(255, color[0], color[1], color[2])
      draw_quad(x, y, c, x + SCALE, y, c, x, y + SCALE, c, x + SCALE, y + SCALE, c)
    end
  end
end

rom_data = File.open(File.expand_path('roms/hello-world.gb', __dir__), 'r') { _1.read.bytes }
Rubyboy::Console.new(rom_data).show
