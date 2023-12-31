# frozen_string_literal: true

module Rubyboy
  class Registers
    attr_reader :value

    def initialize
      @a = 0x01
      @b = 0x00
      @c = 0x13
      @d = 0x00
      @e = 0xd8
      @h = 0x01
      @l = 0x4d
      @f = 0xb0
    end

    def read8(register)
      case register
      when :a then @a
      when :b then @b
      when :c then @c
      when :d then @d
      when :e then @e
      when :h then @h
      when :l then @l
      when :f then @f
      end
    end

    def write8(register, value)
      value &= 0xff
      case register
      when :a then @a = value
      when :b then @b = value
      when :c then @c = value
      when :d then @d = value
      when :e then @e = value
      when :h then @h = value
      when :l then @l = value
      when :f then @f = value & 0xf0
      end
    end

    def read16(register)
      case register
      when :af then (@a << 8) | @f
      when :bc then (@b << 8) | @c
      when :de then (@d << 8) | @e
      when :hl then (@h << 8) | @l
      end
    end

    def write16(register, value)
      value &= 0xffff
      case register
      when :af
        @a = (value >> 8) & 0xff
        @f = value & 0xf0
      when :bc
        @b = (value >> 8) & 0xff
        @c = value & 0xff
      when :de
        @d = (value >> 8) & 0xff
        @e = value & 0xff
      when :hl
        @h = (value >> 8) & 0xff
        @l = value & 0xff
      end
    end

    def increment16(register)
      write16(register, read16(register) + 1)
    end

    def decrement16(register)
      write16(register, read16(register) - 1)
    end
  end
end
