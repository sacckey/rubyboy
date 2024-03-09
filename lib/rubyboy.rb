# frozen_string_literal: true

require 'rubyboy/sdl'
require_relative 'rubyboy/apu'
require_relative 'rubyboy/bus'
require_relative 'rubyboy/cpu'
require_relative 'rubyboy/ppu'
require_relative 'rubyboy/rom'
require_relative 'rubyboy/ram'
require_relative 'rubyboy/timer'
require_relative 'rubyboy/lcd'
require_relative 'rubyboy/joypad'
require_relative 'rubyboy/interrupt'
require_relative 'rubyboy/cartridge/factory'

module Rubyboy
  class Console
    def initialize(rom_path)
      rom_data = File.open(rom_path, 'r') { _1.read.bytes }
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
      @lcd = Lcd.new
    end

    def start
      SDL.InitSubSystem(SDL::INIT_KEYBOARD)
      loop do
        cycles = @cpu.exec
        @timer.step(cycles)
        @apu.step(cycles)
        next unless @ppu.step(cycles)

        @lcd.draw(@ppu.buffer)
        key_input_check
        break if @lcd.window_should_close?
      end
      @lcd.close_window
    rescue StandardError => e
      p e.to_s[0, 100]
      raise e
    end

    def bench
      cnt = 0
      start_time = Time.now
      while cnt < 1500
        cycles = @cpu.exec
        @timer.step(cycles)
        if @ppu.step(cycles)
          key_input_check
          cnt += 1
        end
      end

      Time.now - start_time
    end

    private

    def key_input_check
      SDL.PumpEvents
      keyboard = SDL.GetKeyboardState(nil)
      keyboard_state = keyboard.read_array_of_uint8(229)

      direction = (keyboard_state[SDL::SDL_SCANCODE_D]) | (keyboard_state[SDL::SDL_SCANCODE_A] << 1) | (keyboard_state[SDL::SDL_SCANCODE_W] << 2) | (keyboard_state[SDL::SDL_SCANCODE_S] << 3)
      action = (keyboard_state[SDL::SDL_SCANCODE_K]) | (keyboard_state[SDL::SDL_SCANCODE_J] << 1) | (keyboard_state[SDL::SDL_SCANCODE_U] << 2) | (keyboard_state[SDL::SDL_SCANCODE_I] << 3)
      @joypad.direction_button(15 - direction)
      @joypad.action_button(15 - action)
    end
  end
end
