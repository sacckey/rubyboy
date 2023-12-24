# frozen_string_literal: true

module Rubyboy
  class Timer
    def initialize(interrupt)
      @div = 0
      @tima = 0
      @tma = 0
      @tac = 0
      @cycles = 0
      @interrupt = interrupt
    end

    def step(cycles)
      before_cycles = @cycles
      after_cycles = @cycles + cycles
      @cycles = after_cycles & 0xffff

      @div += after_cycles / 256 - before_cycles / 256
      @div &= 0xffff

      return if @tac[2] == 0

      divider = case @tac & 0b11
                when 0b00 then 1024
                when 0b01 then 16
                when 0b10 then 64
                when 0b11 then 256
                end

      tima_diff = (after_cycles / divider - before_cycles / divider)
      @tima += tima_diff

      return if @tima < 256

      @tima = @tma
      @interrupt.request(:timer)
    end

    def read_byte(byte)
      case byte
      when 0xff04
        @div >> 8
      when 0xff05
        @tima
      when 0xff06
        @tma
      when 0xff07
        @tac | 0b1111_1000
      end
    end

    def write_byte(byte, value)
      case byte
      when 0xff04
        @div = 0
        @cycles = 0
      when 0xff05
        @tima = value
      when 0xff06
        @tma = value
      when 0xff07
        @tac = value & 0b111
      end
    end
  end
end
