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
    CPU_CLOCK_HZ = 4_194_304
    CYCLE_NANOSEC = 1_000_000_000 / CPU_CLOCK_HZ

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

      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      elapsed_machine_time = 0
      catch(:exit_loop) do
        loop do
          elapsed_real_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start_time
          while elapsed_real_time > elapsed_machine_time
            cycles = @cpu.exec
            @timer.step(cycles)
            @apu.step(cycles)
            if @ppu.step(cycles)
              @lcd.draw(@ppu.buffer)
              key_input_check
              throw :exit_loop if @lcd.window_should_close?
            end

            elapsed_machine_time += cycles * CYCLE_NANOSEC
          end
        end
      end
      @lcd.close_window
    rescue StandardError => e
      puts e.to_s[0, 100]
      raise e
    end

    def bench(frames)
      @lcd.close_window
      frame_count = 0
      start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
      while frame_count < frames
        cycles = @cpu.exec
        @timer.step(cycles)
        if @ppu.step(cycles)
          key_input_check
          frame_count += 1
        end
      end

      Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start_time
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
