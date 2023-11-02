# frozen_string_literal: true

require 'json'

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
      @opcodes = File.open('lib/opcodes.json', 'r') { |file| JSON.parse(file.read) }
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
      opcode = read_byte(@pc)
      increment_pc

      cbprefixed = false
      branched = false

      case opcode
      when 0x00 # NOP
      when 0x01 # LD BC, nn
        self.bc = read_word_and_advance_pc
      when 0x0b # DEC BC
        self.bc = bc - 1
      when 0x11 # LD DE, nn
        self.de = read_word_and_advance_pc
      when 0x13 # INC DE
        self.de = de + 1
      when 0x1a # LD A, (DE)
        @a = read_byte(de)
      when 0x18 # JR r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        @pc += byte
      when 0x20 # JR NZ, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        unless flags[:z]
          @pc += byte
          branched = true
        end
      when 0x21 # LD HL, nn
        self.hl = read_word_and_advance_pc
      when 0x22 # LD (HL+), A
        write_byte(hl, @a)
        self.hl = hl + 1
      when 0x38 # JR C, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        if flags[:c]
          @pc += byte
          branched = true
        end
      when 0x3e # LD A, d8
        @a = read_byte_and_advance_pc
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
          z: true,
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
        @pc = read_word_and_advance_pc
      when 0xe0 # LDH (a8), A
        byte = read_byte_and_advance_pc
        write_byte(0xff00 + byte, @a)
      when 0xf0 # LDH A, (a8)
        byte = read_byte_and_advance_pc
        @a = read_byte(0xff00 + byte)
      when 0xf3 # DI
        @ime = false
      when 0xfe # CP d8
        byte = read_byte_and_advance_pc
        update_flags(
          z: @a == byte,
          n: true,
          h: (@a & 0x0f) < (byte & 0x0f),
          c: @a < byte
        )
      else
        raise "unknown opcode: 0x#{'%02x' % opcode}"
      end

      print_log(opcode)

      opcode_kind = cbprefixed ? 'cbprefixed' : 'unprefixed'
      opcode_str = "0x#{'%02X' % opcode}"
      cycles = @opcodes[opcode_kind][opcode_str]['cycles']

      branched ? cycles.max : cycles.min
    end

    private

    def read_byte(addr)
      @bus.read_byte(addr)
    end

    def read_word(addr)
      @bus.read_word(addr)
    end

    def write_byte(addr, value)
      @bus.write_byte(addr, value)
    end

    def write_word(addr, value)
      @bus.write_word(addr, value)
    end

    def read_byte_and_advance_pc
      byte = read_byte(@pc)
      increment_pc
      byte
    end

    def read_word_and_advance_pc
      word = read_word(@pc)
      increment_pc_by_byte(2)
      word
    end

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
      increment_pc_by_byte(1)
    end

    def increment_pc_by_byte(byte)
      @pc += byte
    end

    def convert_to_twos_complement(byte)
      byte = -((byte ^ 0xff) + 1) if byte[7] == 1
      byte
    end
  end
end
