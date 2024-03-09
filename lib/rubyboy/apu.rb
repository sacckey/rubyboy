# frozen_string_literal: true

require_relative 'audio'
require_relative 'apu_channels/channel1'
require_relative 'apu_channels/channel2'
require_relative 'apu_channels/channel3'
require_relative 'apu_channels/channel4'

module Rubyboy
  class Apu
    def initialize
      @audio = Audio.new
      @nr50 = 0
      @nr51 = 0
      @cycles = 0
      @sampling_cycles = 0
      @fs = 0
      @samples = Array.new(1024, 0.0)
      @sample_idx = 0
      @channel1 = ApuChannels::Channel1.new
      @channel2 = ApuChannels::Channel2.new
      @channel3 = ApuChannels::Channel3.new
      @channel4 = ApuChannels::Channel4.new
    end

    def step(cycles)
      @cycles += cycles
      @sampling_cycles += cycles

      @channel1.step(cycles)
      @channel2.step(cycles)
      @channel3.step(cycles)
      @channel4.step(cycles)

      if @cycles >= 0x1fff
        @cycles -= 0x1fff

        @channel1.step_fs(@fs)
        @channel2.step_fs(@fs)
        @channel3.step_fs(@fs)
        @channel4.step_fs(@fs)

        @fs = (@fs + 1) % 8
      end

      if @sampling_cycles >= 87
        @sampling_cycles -= 87

        left_sample = (
          @nr51[7] * @channel4.dac_output +
          @nr51[6] * @channel3.dac_output +
          @nr51[5] * @channel2.dac_output +
          @nr51[4] * @channel1.dac_output
        ) / 4.0

        right_sample = (
          @nr51[3] * @channel4.dac_output +
          @nr51[2] * @channel3.dac_output +
          @nr51[1] * @channel2.dac_output +
          @nr51[0] * @channel1.dac_output
        ) / 4.0

        raise "#{@nr51} #{@channel4.dac_output}, #{@channel3.dac_output}, #{@channel2.dac_output},#{@channel1.dac_output}" if left_sample.abs > 1.0 || right_sample.abs > 1.0

        @samples[@sample_idx * 2] = (@nr50[4..6] / 7.0) * left_sample / 8.0
        @samples[@sample_idx * 2 + 1] = (@nr50[0..2] / 7.0) * right_sample / 8.0
        @sample_idx += 1
      end

      return if @sample_idx < 512

      @sample_idx = 0
      @audio.queue(@samples)
    end

    def read_byte(addr)
      case addr
      when 0xff10..0xff14 then @channel1.read_nr1x(addr - 0xff10)
      when 0xff15..0xff19 then @channel2.read_nr2x(addr - 0xff15)
      when 0xff1a..0xff1e then @channel3.read_nr3x(addr - 0xff1a)
      when 0xff1f..0xff23 then @channel4.read_nr4x(addr - 0xff1f)
      when 0xff24 then @nr50
      when 0xff25 then @nr51
      when 0xff26 then (@channel1.enabled ? 0x01 : 0x00) | (@channel2.enabled ? 0x02 : 0x00) | (@channel3.enabled ? 0x04 : 0x00) | (@channel4.enabled ? 0x08 : 0x00) | 0x70 | (@enabled ? 0x80 : 0x00)
      when 0xff30..0xff3f then @channel3.wave_ram[(addr - 0xff30)]
      else raise "Invalid APU read at #{addr.to_s(16)}"
      end
    end

    def write_byte(addr, val)
      return if !@enabled && ![0xff11, 0xff16, 0xff1b, 0xff20, 0xff26].include?(addr) && !(0xff30..0xff3f).include?(addr)

      val &= 0x3f if !@enabled && [0xff11, 0xff16, 0xff1b, 0xff20].include?(addr)

      case addr
      when 0xff10..0xff14 then @channel1.write_nr1x(addr - 0xff10, val)
      when 0xff15..0xff19 then @channel2.write_nr2x(addr - 0xff15, val)
      when 0xff1a..0xff1e then @channel3.write_nr3x(addr - 0xff1a, val)
      when 0xff1f..0xff23 then @channel4.write_nr4x(addr - 0xff1f, val)
      when 0xff24 then @nr50 = val
      when 0xff25 then @nr51 = val
      when 0xff26
        flg = val & 0x80 > 0
        if !flg && @enabled
          (0xff10..0xff25).each { |a| write_byte(a, 0) }
        elsif flg && !@enabled
          @fs = 0
          @channel1.wave_duty_position = 0
          @channel2.wave_duty_position = 0
          @channel3.wave_duty_position = 0
        end
        @enabled = flg
      when 0xff30..0xff3f then @channel3.wave_ram[(addr - 0xff30)] = val
      else raise "Invalid APU write at #{addr.to_s(16)}"
      end
    end
  end
end
