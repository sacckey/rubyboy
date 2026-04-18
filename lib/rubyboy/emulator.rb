# frozen_string_literal: true

module Rubyboy
  class Emulator
    CPU_CLOCK_HZ = 4_194_304
    CYCLE_NANOSEC = 1_000_000_000 / CPU_CLOCK_HZ
    SAVE_STATE_KEYS = [
      SDL::SDL_SCANCODE_1,
      SDL::SDL_SCANCODE_2,
      SDL::SDL_SCANCODE_3,
      SDL::SDL_SCANCODE_4,
      SDL::SDL_SCANCODE_5,
      SDL::SDL_SCANCODE_6,
      SDL::SDL_SCANCODE_7,
      SDL::SDL_SCANCODE_8,
      SDL::SDL_SCANCODE_9,
      SDL::SDL_SCANCODE_0
    ].freeze

    def initialize(rom_path)
      @rom_path = rom_path
      rom_data = File.open(rom_path, 'r') { _1.read.bytes }
      @rom = Rom.new(rom_data)
      @ram = Ram.new(@rom)
      @mbc = Cartridge::Factory.create(@rom, @ram)
      @interrupt = Interrupt.new
      @ppu = Ppu.new(@interrupt)
      @timer = Timer.new(@interrupt)
      @joypad = Joypad.new(@interrupt)
      @apu = Apu.new
      @bus = Bus.new(@ppu, @rom, @ram, @mbc, @timer, @interrupt, @joypad, @apu)
      @cpu = Cpu.new(@bus, @interrupt)
      @lcd = Lcd.new
      @audio = Audio.new
      @prev_save_state_keys = Array.new(SAVE_STATE_KEYS.size, 0)
      @save_file = @rom.battery? ? SaveFile.new(default_save_path(rom_path)) : nil
      load_save_file
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
            @audio.queue(@apu.samples) if @apu.step(cycles)
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
    ensure
      save_save_file
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

    def save_state(slot: nil, path: nil)
      state_path = path || slot_path(slot)
      return false unless StateFile.write(state_path, rom: @rom) { hardware_state }

      puts "Saved state to #{state_path}"
      true
    end

    def load_state(slot: nil, path: nil)
      state_path = path || slot_path(slot)
      return false unless StateFile.read(state_path, rom: @rom) { |state| restore_hardware_state(state) }

      puts "Loaded state from #{state_path}"
      true
    end

    private

    def default_save_path(rom_path)
      dir = File.dirname(rom_path)
      base = File.basename(rom_path, '.*')
      File.join(dir, "#{base}.sav")
    end

    def slot_path(slot)
      raise ArgumentError, 'slot must be between 0 and 9' unless (0..9).cover?(slot)

      dir = File.dirname(@rom_path)
      base = File.basename(@rom_path, '.*')
      File.join(dir, "#{base}.state#{slot}")
    end

    def hardware_state
      {
        schema: 'game_boy_console_and_cartridge',
        console: {
          cpu: @cpu.hardware_state,
          ram: @ram.hardware_state,
          ppu: @ppu.hardware_state,
          apu: @apu.hardware_state,
          timer: @timer.hardware_state,
          interrupt: @interrupt.hardware_state,
          joypad: @joypad.hardware_state
        },
        cartridge: @mbc.hardware_state
      }
    end

    def restore_hardware_state(state)
      console = state.fetch(:console)
      @cpu.restore_hardware_state(console.fetch(:cpu))
      @ram.restore_hardware_state(console.fetch(:ram))
      @ppu.restore_hardware_state(console.fetch(:ppu))
      @apu.restore_hardware_state(console.fetch(:apu))
      @timer.restore_hardware_state(console.fetch(:timer))
      @interrupt.restore_hardware_state(console.fetch(:interrupt))
      @joypad.restore_hardware_state(console.fetch(:joypad))
      @mbc.restore_hardware_state(state.fetch(:cartridge))
    end

    def load_save_file
      return unless @save_file

      bytes = @save_file.read(@ram.eram.size)
      return unless bytes

      @ram.eram.replace(bytes)
      puts "Loaded save from #{@save_file.path}"
    end

    def save_save_file
      return unless @save_file

      puts "Saved to #{@save_file.path}" if @save_file.write(@ram.eram)
    end

    def key_input_check
      SDL.PumpEvents
      keyboard = SDL.GetKeyboardState(nil)
      keyboard_state = keyboard.read_array_of_uint8(229)

      check_state_save_keys(keyboard_state)
      direction = (keyboard_state[SDL::SDL_SCANCODE_D]) | (keyboard_state[SDL::SDL_SCANCODE_A] << 1) | (keyboard_state[SDL::SDL_SCANCODE_W] << 2) | (keyboard_state[SDL::SDL_SCANCODE_S] << 3)
      action = (keyboard_state[SDL::SDL_SCANCODE_K]) | (keyboard_state[SDL::SDL_SCANCODE_J] << 1) | (keyboard_state[SDL::SDL_SCANCODE_U] << 2) | (keyboard_state[SDL::SDL_SCANCODE_I] << 3)
      @joypad.direction_button(15 - direction)
      @joypad.action_button(15 - action)
    end

    def check_state_save_keys(keyboard_state)
      shift = keyboard_state[SDL::SDL_SCANCODE_LSHIFT] > 0
      SAVE_STATE_KEYS.each_with_index do |key, index|
        pressed = keyboard_state[key]
        next unless pressed > 0 && @prev_save_state_keys[index] == 0

        shift ? load_state(slot: index) : save_state(slot: index)
      ensure
        @prev_save_state_keys[index] = pressed
      end
    end
  end
end
