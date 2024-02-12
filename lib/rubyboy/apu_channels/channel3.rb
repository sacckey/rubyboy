# frozen_string_literal: true

module Rubyboy
  module ApuChannels
    class Channel3
      attr_accessor :enabled, :wave_duty_position, :wave_ram

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

        @output_level = 0
        @volume_shift = 0
        @wave_ram = Array.new(16, 0)
      end

      def step(cycles)
        @cycles += cycles

        if @cycles >= @frequency_timer
          @cycles -= @frequency_timer
          @frequency_timer = (2048 - @frequency) * 2
          @wave_duty_position = (@wave_duty_position + 1) % 32
        end
      end

      def step_fs(fs)
        length if fs & 0x01 == 0
      end

      def length
        if @length_enabled && @length_timer > 0
          @length_timer -= 1
          @enabled &= @length_timer > 0
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

        ret = ((0xf & (
          @wave_ram[@wave_duty_position >> 1] >> ((@wave_duty_position & 0x01) << 2)
        ))) >> @volume_shift

        (ret / 7.5) - 1.0
      end

      def read_nr3x(x)
        case x
        when 0 then ((@dac_enabled ? 0x80 : 0x00) | 0x7f)
        when 1 then 0xff
        when 2 then (@output_level << 5) | 0x9f
        when 3 then 0xff
        when 4 then (@length_enabled ? 0x40 : 0x00) | 0xbf
        else 0xff
        end
      end

      def write_nr3x(x, val)
        case x
        when 0
          @dac_enabled = val & 0x80 > 0
          @enabled &= @dac_enabled
        when 1
          @length_timer = 256 - val
        when 2
          @output_level = (val >> 5) & 0x03
        when 3
          @frequency = (@frequency & 0x700) | val
        when 4
          @frequency = (@frequency & 0xff) | ((val & 0x07) << 8)
          @length_enabled = val & 0x40 > 0
          @length_timer = 256 if @length_timer == 0
          @enabled = true if (val & 0x80) > 0 && @dac_enabled
        end
      end
    end
  end
end
