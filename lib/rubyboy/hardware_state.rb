# frozen_string_literal: true

module Rubyboy
  class Registers
    def hardware_state
      { af:, bc:, de:, hl: }
    end

    def restore_hardware_state(state)
      self.af = state.fetch(:af)
      self.bc = state.fetch(:bc)
      self.de = state.fetch(:de)
      self.hl = state.fetch(:hl)
    end
  end

  class Cpu
    def hardware_state
      {
        registers: @registers.hardware_state,
        pc: @pc,
        sp: @sp,
        ime: @ime,
        ime_delay: @ime_delay,
        halted: @halted
      }
    end

    def restore_hardware_state(state)
      @registers.restore_hardware_state(state.fetch(:registers))
      @pc = state.fetch(:pc)
      @sp = state.fetch(:sp)
      @ime = state.fetch(:ime)
      @ime_delay = state.fetch(:ime_delay)
      @halted = state.fetch(:halted)
    end
  end

  class Timer
    def hardware_state
      {
        div: @div,
        tima: @tima,
        tma: @tma,
        tac: @tac,
        divider_phase: @cycles
      }
    end

    def restore_hardware_state(state)
      @div = state.fetch(:div)
      @tima = state.fetch(:tima)
      @tma = state.fetch(:tma)
      @tac = state.fetch(:tac)
      @cycles = state.fetch(:divider_phase)
    end
  end

  class Interrupt
    def hardware_state
      { ie: @ie, if: @if }
    end

    def restore_hardware_state(state)
      @ie = state.fetch(:ie)
      @if = state.fetch(:if)
    end
  end

  class Joypad
    def hardware_state
      {
        p1_select: @mode,
        action_buttons: @action,
        direction_buttons: @direction
      }
    end

    def restore_hardware_state(state)
      @mode = state.fetch(:p1_select)
      @action = state.fetch(:action_buttons)
      @direction = state.fetch(:direction_buttons)
    end
  end

  class Ram
    def hardware_state
      {
        eram: @eram.dup,
        wram1: @wram1.dup,
        wram2: @wram2.dup,
        hram: @hram.dup
      }
    end

    def restore_hardware_state(state)
      @eram = state.fetch(:eram).dup
      @wram1 = state.fetch(:wram1).dup
      @wram2 = state.fetch(:wram2).dup
      @hram = state.fetch(:hram).dup
    end
  end

  class Ppu
    def hardware_state
      {
        registers: {
          lcdc: @lcdc,
          stat: @stat,
          scy: @scy,
          scx: @scx,
          ly: @ly,
          lyc: @lyc,
          obp0: @obp0,
          obp1: @obp1,
          wy: @wy,
          wx: @wx,
          bgp: @bgp
        },
        vram: @vram.dup,
        oam: @oam.dup,
        mode: @mode,
        dot_phase: @cycles,
        window_line: @wly
      }
    end

    def restore_hardware_state(state)
      registers = state.fetch(:registers)
      @lcdc = registers.fetch(:lcdc)
      @stat = registers.fetch(:stat)
      @scy = registers.fetch(:scy)
      @scx = registers.fetch(:scx)
      @ly = registers.fetch(:ly)
      @lyc = registers.fetch(:lyc)
      @obp0 = registers.fetch(:obp0)
      @obp1 = registers.fetch(:obp1)
      @wy = registers.fetch(:wy)
      @wx = registers.fetch(:wx)
      @bgp = registers.fetch(:bgp)
      @vram = state.fetch(:vram).dup
      @oam = state.fetch(:oam).dup
      @mode = state.fetch(:mode)
      @cycles = state.fetch(:dot_phase)
      @wly = state.fetch(:window_line)
      rebuild_render_caches
    end

    private

    def rebuild_render_caches
      @buffer = Array.new(144 * 160, 0xffffffff)
      @bg_pixels = Array.new(LCD_WIDTH, 0x00)
      @tile_cache = Array.new(384) { Array.new(64, 0) }
      @tile_map_cache = Array.new(2048, 0)
      @bgp_cache = Array.new(4, 0xffffffff)
      @obp0_cache = Array.new(4, 0xffffffff)
      @obp1_cache = Array.new(4, 0xffffffff)
      @sprite_cache = Array.new(40) { { y: 0xff, x: 0xff, tile_index: 0, flags: 0 } }

      (0...0x1800).step(2) { |addr| update_tile_cache(addr) }
      refresh_tile_map_cache
      refresh_palette_cache(@bgp_cache, @bgp)
      refresh_palette_cache(@obp0_cache, @obp0)
      refresh_palette_cache(@obp1_cache, @obp1)
      40.times do |sprite_index|
        base = sprite_index << 2
        @sprite_cache[sprite_index][:y] = (@oam[base] - 16) & 0xff
        @sprite_cache[sprite_index][:x] = (@oam[base + 1] - 8) & 0xff
        @sprite_cache[sprite_index][:tile_index] = @oam[base + 2]
        @sprite_cache[sprite_index][:flags] = @oam[base + 3]
      end
    end
  end

  module ApuChannels
    module ChannelHardwareState
      HARDWARE_FIELDS = %i[
        cycles frequency frequency_timer wave_duty_position enabled dac_enabled length_enabled
        is_upwards is_decrementing sweep_enabled sweep_period sweep_shift period period_timer
        current_volume initial_volume shadow_frequency sweep_timer length_timer wave_duty_pattern
        output_level volume_shift wave_ram lfsr width_mode shift_amount divisor_code
      ].freeze

      def hardware_state
        HARDWARE_FIELDS.each_with_object({}) do |name, state|
          ivar = "@#{name}"
          state[name] = instance_variable_get(ivar) if instance_variable_defined?(ivar)
        end
      end

      def restore_hardware_state(state)
        state.each { |name, value| instance_variable_set("@#{name}", value) }
      end
    end

    Channel1.include(ChannelHardwareState)
    Channel2.include(ChannelHardwareState)
    Channel3.include(ChannelHardwareState)
    Channel4.include(ChannelHardwareState)
  end

  class Apu
    def hardware_state
      {
        nr50: @nr50,
        nr51: @nr51,
        frame_sequencer_phase: @cycles,
        sample_phase: @sampling_accumulator,
        frame_sequencer_step: @fs,
        enabled: @enabled,
        channels: {
          channel1: @channel1.hardware_state,
          channel2: @channel2.hardware_state,
          channel3: @channel3.hardware_state,
          channel4: @channel4.hardware_state
        }
      }
    end

    def restore_hardware_state(state)
      @nr50 = state.fetch(:nr50)
      @nr51 = state.fetch(:nr51)
      @cycles = state.fetch(:frame_sequencer_phase)
      @sampling_accumulator = state.fetch(:sample_phase)
      @fs = state.fetch(:frame_sequencer_step)
      @enabled = state.fetch(:enabled)
      channels = state.fetch(:channels)
      @channel1.restore_hardware_state(channels.fetch(:channel1))
      @channel2.restore_hardware_state(channels.fetch(:channel2))
      @channel3.restore_hardware_state(channels.fetch(:channel3))
      @channel4.restore_hardware_state(channels.fetch(:channel4))
      @samples = Array.new(1024, 0.0)
      @sample_idx = 0
    end
  end

  module Cartridge
    class Mbc1
      def hardware_state
        {
          type: 'mbc1',
          rom_bank_low: @rom_bank,
          ram_bank_high: @ram_bank,
          ram_enabled: @ram_enable,
          banking_mode: @ram_banking_mode
        }
      end

      def restore_hardware_state(state)
        @rom_bank = state.fetch(:rom_bank_low)
        @ram_bank = state.fetch(:ram_bank_high)
        @ram_enable = state.fetch(:ram_enabled)
        @ram_banking_mode = state.fetch(:banking_mode)
      end
    end

    class Nombc
      def hardware_state
        { type: 'nombc' }
      end

      def restore_hardware_state(_state)
        true
      end
    end
  end
end
