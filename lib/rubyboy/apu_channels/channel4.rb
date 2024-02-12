# frozen_string_literal: true

module Rubyboy
  module ApuChannels
    class Channel4
      attr_accessor :enabled, :wave_duty_position

      WAVE_DUTY = [
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0], # 12.5%
        [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0], # 25%
        [0.0, 0.0, 0.0, 0.0, 1.0, 1.0, 1.0, 1.0], # 50%
        [0.0, 0.0, 1.0, 1.0, 1.0, 1.0, 1.0, 1.0]  # 75%
      ].freeze

      def initialize
        @cycles = 0
        @frequency = 0
        @frequency_timer = 0
        @wave_duty_position = 0

        @enabled = false
        @dac_enabled = false
        @length_enabled = false
        @is_upwards = false
        @is_decrementing = false
        @sweep_enabled = false
        @sweep_period = 0
        @sweep_shift = 0
        @period = 0
        @period_timer = 0
        @current_volume = 0
        @initial_volume = 0
        @shadow_frequency = 0
        @sweep_timer = 0
        @length_timer = 0
        @wave_duty_pattern = 0

        @lfsr = 0x7fff
        @width_mode = false
        @shift_amount = 0
        @divisor_code = 0
      end

      def step(cycles)
        @cycles += cycles

        if @cycles >= @frequency_timer
          @cycles -= @frequency_timer
          @frequency_timer = [8, @divisor_code << 4].max << @shift_amount

          xor = (@lfsr & 0x01) ^ ((@lfsr & 0b10) >> 1)
          @lfsr = (@lfsr >> 1) | (xor << 14)
          if @width_mode
            @lfsr &= ~(1 << 6)
            @lfsr |= xor << 6
          end
        end
      end

      def step_fs(fs)
        length if fs & 0x01 == 0
        envelope if fs == 7
      end

      def length
        if @length_enabled && @length_timer > 0
          @length_timer -= 1
          @enabled &= @length_timer > 0
        end
      end

      def envelope
        return if @period == 0

        @period_timer -= 1 if @period_timer > 0

        return if @period_timer != 0

        @period_timer = @period

        if @current_volume < 15 && @is_upwards
          @current_volume += 1
        elsif @current_volume > 0 && !@is_upwards
          @current_volume -= 1
        end
      end

      def calculate_frequency
        if @is_decrementing
          if @shadow_frequency >= (@shadow_frequency >> @sweep_shift)
            @shadow_frequency - (@shadow_frequency >> @sweep_shift)
          else
            0
          end
        else
          [0x3ff, @shadow_frequency + (@shadow_frequency >> @sweep_shift)].min
        end
      end

      def dac_output
        return 0.0 unless @dac_enabled && @enabled

        ret = (@lfsr & 0x01) * @current_volume
        (ret / 7.5) - 1.0
      end

      def read_nr4x(x)
        case x
        when 0 then 0xff
        when 1 then 0xff
        when 2 then (@initial_volume << 4) | (@is_upwards ? 0x08 : 0x00) | @period
        when 3 then (@shift_amount << 4) | (@width_mode ? 0x08 : 0x00) | @divisor_code
        when 4 then (@length_enabled ? 0x40 : 0x00) | 0xbf
        else 0xff
        end
      end

      def write_nr4x(x, val)
        case x
        when 0
          # nop
        when 1
          @length_timer = 64 - (val & 0x3f)
        when 2
          @is_upwards = (val & 0x08) > 0
          @initial_volume = val >> 4
          @period = val & 0x07
          @dac_enabled = val & 0xf8 > 0
          @enabled &= @dac_enabled
        when 3
          @shift_amount = (val >> 4) & 0x0f
          @width_mode = (val & 0x08) > 0
          @divisor_code = val & 0x07
        when 4
          @length_enabled = (val & 0x40) > 0
          @length_timer = 64 if @length_timer == 0
          return unless (val & 0x80) > 0

          @enabled = true if @dac_enabled

          @lfsr = 0x7fff
          @period_timer = @period
          @current_volume = @initial_volume
        end
      end
    end
  end
end
