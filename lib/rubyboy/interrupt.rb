# frozen_string_literal: true

module Rubyboy
  class Interrupt
    INTERRUPTS = {
      vblank: 0,
      lcd: 1,
      timer: 2,
      serial: 3,
      joypad: 4
    }.freeze

    def initialize
      @ie = 0
      @if = 0
    end

    def read_byte(addr)
      case addr
      when 0xff0f
        @if
      when 0xffff
        @ie
      end
    end

    def write_byte(addr, value)
      case addr
      when 0xff0f
        @if = value
      when 0xffff
        @ie = value
      end
    end

    def interrupts
      @if & @ie & 0x1f
    end

    def request(interrupt)
      @if |= (1 << INTERRUPTS[interrupt])
    end

    def reset_flag(i)
      @if &= (~(1 << i)) & 0xff
    end
  end
end
