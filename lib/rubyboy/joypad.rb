# frozen_string_literal: true

module Rubyboy
  class Joypad
    def initialize(interupt)
      @mode = 0xcf
      @action = 0xff
      @direction = 0xff
      @interupt = interupt
    end

    def read_byte(addr)
      raise "not implemented: write_byte #{addr}" unless addr == 0xff00

      res = @mode | 0xcf
      res &= @direction if @mode[4] == 0
      res &= @action if @mode[5] == 0

      res
    end

    def write_byte(addr, value)
      raise "not implemented: write_byte #{addr}" unless addr == 0xff00

      @mode = value & 0x30
      @mode |= 0xc0
    end

    def direction_button(button)
      @direction = button | 0xf0

      @interupt.request(:joypad) if button < 0b1111
    end

    def action_button(button)
      @action = button | 0xf0

      @interupt.request(:joypad) if button < 0b1111
    end
  end
end
