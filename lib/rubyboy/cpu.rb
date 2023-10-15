# frozen_string_literal: true

module Rubyboy
  class Cpu
    attr_accessor :a, :b, :c, :d, :e, :h, :l, :f, :pc, :sp, :ime, :bus

    def initialize(bus)
      @a = 0x01
      @b = 0x00
      @c = 0x13
      @d = 0x00
      @e = 0xd8
      @h = 0x01
      @l = 0x4d
      @f = 0xb0
      @pc = 0x0100
      @sp = 0xfffe
      @ime = false
      @bus = bus
    end

    def bc
      (@b << 8) + @c
    end

    def bc=(value)
      @b = value >> 8
      @c = value & 0xff
    end

    def de
      (@d << 8) + @e
    end

    def de=(value)
      @d = value >> 8
      @e = value & 0xff
    end

    def hl
      (@h << 8) + @l
    end

    def hl=(value)
      @h = value >> 8
      @l = value & 0xff
    end

    def exec
      opcode = @bus.read_byte(@pc)
      increment_pc
      # TODO: Set valid clock
      clock = 4

      case opcode
      when 0x00 # NOP
      when 0x01 # LD BC, nn
        @c = @bus.read_byte(@pc)
        increment_pc
        @b = @bus.read_byte(@pc)
        increment_pc
      when 0x0b # DEC BC
        self.bc = bc - 1
      when 0x11 # LD DE, nn
        @e = @bus.read_byte(@pc)
        increment_pc
        @d = @bus.read_byte(@pc)
        increment_pc
      when 0x13 # INC DE
        self.de = de + 1
      when 0x1a # LD A, (DE)
        @a = @bus.read_byte(de)
      when 0x18 # JR r8
        byte = to_signed_byte(@bus.read_byte(@pc))
        increment_pc
        @pc += byte
      when 0x20 # JR NZ, r8
        byte = to_signed_byte(@bus.read_byte(@pc))
        increment_pc
        @pc += byte unless flags[:z]
      when 0x21 # LD HL, nn
        @l = @bus.read_byte(@pc)
        increment_pc
        @h = @bus.read_byte(@pc)
        increment_pc
      when 0x22 # LD (HL+), A
        @bus.write_byte(hl, @a)
        self.hl = hl + 1
      when 0x38 # JR C, r8
        byte = to_signed_byte(@bus.read_byte(@pc))
        increment_pc
        @pc += byte if flags[:c]
      when 0x3e # LD A, d8
        @a = @bus.read_byte(@pc)
        increment_pc
      when 0x40 # LD B, B
        # @b = @b
      when 0x42 # LD B, D
        @b = @d
      when 0x43 # LD B, E
        @b = @e
      when 0x78 # LD A, B
        @a = @b
      when 0xa7 # AND A
        @a &= @a
        update_flags(
          z: @a.zero?,
          n: false,
          h: true,
          c: false
        )
      when 0xaf # XOR A
        @a ^= @a
        update_flags(
          z: @a.zero?,
          n: false,
          h: false,
          c: false
        )
      when 0xb1 # OR C
        @a |= @c
        update_flags(
          z: @a.zero?,
          n: false,
          h: false,
          c: false
        )
      when 0xc3 # JP nn
        @pc = @bus.read_word(@pc)
      when 0xe0 # LDH (a8), A
        byte = @bus.read_byte(@pc)
        @bus.write_byte(0xff00 + byte, @a)
        increment_pc
      when 0xf0 # LDH A, (a8)
        byte = @bus.read_byte(@pc)
        @a = @bus.read_byte(0xff00 + byte)
        increment_pc
      when 0xf3 # DI
        @ime = false
      when 0xfe # CP d8
        byte = @bus.read_byte(@pc)
        update_flags(
          z: @a == byte,
          n: true,
          h: (@a & 0x0f) < (byte & 0x0f),
          c: @a < byte
        )
        increment_pc
      else
        raise "unknown opcode: 0x#{'%02x' % opcode}"
      end

      print_log(opcode)

      clock
    end

    private

    def print_log(opcode)
      puts "OP: 0x#{'%02x' % opcode}, PC: 0x#{'%04x' % @pc}, SP: 0x#{'%04x' % @sp}, A: 0x#{'%02x' % @a}, B: 0x#{'%02x' % @b}, C: 0x#{'%02x' % @c}, D: 0x#{'%02x' % @d}, E: 0x#{'%02x' % @e}, H: 0x#{'%02x' % @h}, L: 0x#{'%02x' % @l}, F: 0x#{'%02x' % @f}"
    end

    def flags
      {
        z: @f[7] == 1,
        n: @f[6] == 1,
        h: @f[5] == 1,
        c: @f[4] == 1
      }
    end

    def update_flags(z:, n:, h:, c:)
      @f = 0x00
      @f |= 0x80 if z
      @f |= 0x40 if n
      @f |= 0x20 if h
      @f |= 0x10 if c
    end

    def bool_to_integer(bool)
      bool ? 1 : 0
    end

    def increment_pc
      @pc += 1
    end

    def to_signed_byte(byte)
      byte = -((byte ^ 0xff) + 1) if byte[7] == 1
      byte
    end
  end
end
