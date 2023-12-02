# frozen_string_literal: true

require 'raylib'
require_relative 'rubyboy/bus'
require_relative 'rubyboy/cpu'
require_relative 'rubyboy/ppu'
require_relative 'rubyboy/rom'
require_relative 'rubyboy/timer'
require_relative 'rubyboy/lcd'
require_relative 'rubyboy/joypad'
require_relative 'rubyboy/interrupt'

module Rubyboy
  class Console
    include Raylib

    def initialize(rom_path)
      load_raylib
      rom_data = File.open(rom_path, 'r') { _1.read.bytes }
      rom = Rom.new(rom_data)
      interrupt = Interrupt.new
      @ppu = Ppu.new(interrupt)
      @timer = Timer.new(interrupt)
      @joypad = Joypad.new(interrupt)
      @bus = Bus.new(@ppu, rom, @timer, interrupt, @joypad)
      @cpu = Cpu.new(@bus, interrupt)
      @lcd = Lcd.new
    end

    def start
      until @lcd.window_should_close?
        cycles = @cpu.exec
        @timer.step(cycles)
        if @ppu.step(cycles)
          draw
          key_input_check
        end
      end
      @lcd.close_window
    rescue StandardError => e
      p e.to_s[0, 100]
      raise e
    end

    private

    def draw
      pixel_data = buffer_to_pixel_data(@ppu.buffer)
      @lcd.draw(pixel_data)
    end

    def buffer_to_pixel_data(buffer)
      buffer.map do |row|
        [row, row, row]
      end.flatten.pack('C*')
    end

    def key_input_check
      direction = (IsKeyUp(KEY_D) && 1 || 0) | ((IsKeyUp(KEY_A) && 1 || 0) << 1) | ((IsKeyUp(KEY_W) && 1 || 0) << 2) | ((IsKeyUp(KEY_S) && 1 || 0) << 3)
      action = (IsKeyUp(KEY_K) && 1 || 0) | ((IsKeyUp(KEY_J) && 1 || 0) << 1) | ((IsKeyUp(KEY_U) && 1 || 0) << 2) | ((IsKeyUp(KEY_I) && 1 || 0) << 3)
      @joypad.direction_button(direction)
      @joypad.action_button(action)
    end

    def load_raylib
      shared_lib_path = "#{Gem::Specification.find_by_name('raylib-bindings').full_gem_path}/lib/"
      case RUBY_PLATFORM
      when /mswin|msys|mingw/ # Windows
        Raylib.load_lib("#{shared_lib_path}libraylib.dll")
      when /darwin/ # macOS
        Raylib.load_lib("#{shared_lib_path}libraylib.dylib")
      when /linux/ # Ubuntu Linux (x86_64 or aarch64)
        arch = RUBY_PLATFORM.split('-')[0]
        Raylib.load_lib(shared_lib_path + "libraylib.#{arch}.so")
      else
        raise "Unknown system: #{RUBY_PLATFORM}"
      end

      SetTraceLogLevel(LOG_ERROR)
    end
  end
end
