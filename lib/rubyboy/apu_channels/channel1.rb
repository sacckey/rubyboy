# frozen_string_literal: true

module Rubyboy
  module ApuChannels
    class Channel1
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
      end

      def step(cycles)
        @cycles += cycles

        return if @cycles < @frequency_timer

        @cycles -= @frequency_timer
        @frequency_timer = (2048 - @frequency) * 4
        @wave_duty_position = (@wave_duty_position + 1) % 8
      end

      def step_fs(fs)
        length if fs & 0x01 == 0
        envelope if fs == 7
        sweep if fs == 2 || fs == 6
      end

      def length
        return unless @length_enabled && @length_timer > 0

        @length_timer -= 1
        @enabled &= @length_timer > 0
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

      def sweep
        @sweep_timer -= 1 if @sweep_timer > 0

        return if @sweep_timer != 0

        @sweep_timer = @sweep_period

        return unless @sweep_enabled

        @frequency = calculate_frequency
        @shadow_frequency = @frequency
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

        ret = WAVE_DUTY[@wave_duty_pattern][@wave_duty_position] * @current_volume
        (ret / 7.5) - 1.0
      end

      def read_nr1x(x)
        case x
        when 0 then (@sweep_period << 4) | @sweep_shift | (@is_decrementing ? 0x08 : 0x00) | 0x80
        when 1 then (@wave_duty_pattern << 6) | 0x3f
        when 2 then (@initial_volume << 4) | (@is_upwards ? 0x08 : 0x00) | @period
        when 3 then 0xff
        when 4 then (@length_enabled ? 0x40 : 0x00) | 0xbf
        else 0xff
        end
      end

      def write_nr1x(x, val)
        case x
        when 0
          @sweep_period = (val >> 4) & 0x07
          @is_decrementing = (val & 0x08) > 0
          @sweep_shift = val & 0x07
        when 1
          @wave_duty_pattern = (val >> 6) & 0x03
          @length_timer = 64 - (val & 0x3f)
        when 2
          @is_upwards = (val & 0x08) > 0
          @initial_volume = (val >> 4)
          @period = val & 0x07
          @dac_enabled = val & 0xf8 > 0
          @enabled &= @dac_enabled
        when 3
          @frequency = (@frequency & 0x700) | val
        when 4
          @frequency = (@frequency & 0xff) | ((val & 0x07) << 8)
          @length_enabled = (val & 0x40) > 0
          @length_timer = 64 if @length_timer == 0
          return unless (val & 0x80) > 0 && @dac_enabled

          @enabled = true
          @period_timer = @period
          @current_volume = @initial_volume
          @shadow_frequency = @frequency
          @sweep_timer = @sweep_period
          @sweep_enabled = @sweep_period > 0 || @sweep_shift > 0
        end
      end
    end
  end
end
