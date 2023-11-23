# frozen_string_literal: true

require 'json'
require_relative 'register'

module Rubyboy
  class Cpu
    def initialize(bus, interrupt)
      @a = Register.new(name: 'a', value: 0x01)
      @b = Register.new(name: 'b', value: 0x00)
      @c = Register.new(name: 'c', value: 0x13)
      @d = Register.new(name: 'd', value: 0x00)
      @e = Register.new(name: 'e', value: 0xd8)
      @h = Register.new(name: 'h', value: 0x01)
      @l = Register.new(name: 'l', value: 0x4d)
      @f = Register.new(name: 'f', value: 0xb0)

      @pc = 0x0100
      @sp = 0xfffe
      @ime = false
      @ime_delay = false
      @bus = bus
      @interrupt = interrupt
      @opcodes = File.open('lib/opcodes.json', 'r') { |file| JSON.parse(file.read) }
      @halted = false

      @cnt = 0
    end

    def af
      (@a.value << 8) + @f.value
    end

    def af=(value)
      value &= 0xffff
      @a.value = value >> 8
      @f.value = value & 0xf0
    end

    def bc
      (@b.value << 8) + @c.value
    end

    def bc=(value)
      value &= 0xffff
      @b.value = value >> 8
      @c.value = value & 0xff
    end

    def de
      (@d.value << 8) + @e.value
    end

    def de=(value)
      value &= 0xffff
      @d.value = value >> 8
      @e.value = value & 0xff
    end

    def hl
      (@h.value << 8) + @l.value
    end

    def hl=(value)
      value &= 0xffff
      @h.value = value >> 8
      @l.value = value & 0xff
    end

    def exec
      opcode = read_byte(@pc)
      # print_log(opcode)

      @halted &= @interrupt.interrupts.zero?

      return 16 if @halted

      in_interrupt = false

      if @ime && @interrupt.interrupts.positive?
        in_interrupt = true
      else
        increment_pc
      end

      if in_interrupt
        pcs = [0x0040, 0x0048, 0x0050, 0x0058, 0x0060]
        5.times do |i|
          next if @interrupt.interrupts[i].zero?

          @interrupt.reset_flag(i)
          @ime = false
          @sp -= 2
          @bus.write_word(@sp, @pc)
          @pc = pcs[i]
          break
        end
        return 20
      end

      if @ime_delay
        @ime_delay = false
        @ime = true
      end

      cbprefixed = false
      branched = false

      case opcode
      when 0x00 # NOP
      when 0x01 # LD BC, nn
        self.bc = read_word_and_advance_pc
      when 0x02 # LD (BC), A
        write_byte(bc, @a.value)
      when 0x03 # INC BC
        self.bc = bc + 1
      when 0x04 # INC B
        @b.increment
        update_flags(
          z: @b.value.zero?,
          n: false,
          h: (@b.value & 0x0f).zero?
        )
      when 0x05 # DEC B
        @b.decrement
        update_flags(
          z: @b.value.zero?,
          n: true,
          h: (@b.value & 0x0f) == 0x0f
        )
      when 0x06 # LD B, d8
        @b.value = read_byte_and_advance_pc
      when 0x07 # RLCA
        @a.value = (@a.value << 1) | (@a.value >> 7)
        update_flags(
          z: false,
          n: false,
          h: false,
          c: @a.value[0] == 1
        )
      when 0x08 # LD (nn), SP
        word = read_word_and_advance_pc
        write_word(word, @sp)
      when 0x09 # ADD HL, BC
        hflag = (hl & 0x0fff) + (bc & 0x0fff) > 0x0fff
        cflag = hl + bc > 0xffff
        self.hl = hl + bc
        update_flags(
          n: false,
          h: hflag,
          c: cflag
        )
      when 0x0a # LD A, (BC)
        @a.value = read_byte(bc)
      when 0x0b # DEC BC
        self.bc = bc - 1
      when 0x0c # INC C
        @c.increment
        update_flags(
          z: @c.value.zero?,
          n: false,
          h: (@c.value & 0x0f).zero?
        )
      when 0x0d # DEC C
        @c.decrement
        update_flags(
          z: @c.value.zero?,
          n: true,
          h: (@c.value & 0x0f) == 0x0f
        )
      when 0x0e # LD C, d8
        @c.value = read_byte_and_advance_pc
      when 0x0f # RRCA
        @a.value = (@a.value >> 1) | (@a.value << 7)
        update_flags(
          z: false,
          n: false,
          h: false,
          c: @a.value[7] == 1
        )
      when 0x10 # STOP
      when 0x11 # LD DE, nn
        self.de = read_word_and_advance_pc
      when 0x12 # LD (DE), A
        write_byte(de, @a.value)
      when 0x13 # INC DE
        self.de = de + 1
      when 0x14 # INC D
        @d.increment
        update_flags(
          z: @d.value.zero?,
          n: false,
          h: (@d.value & 0x0f).zero?
        )
      when 0x15 # DEC D
        @d.decrement
        update_flags(
          z: @d.value.zero?,
          n: true,
          h: (@d.value & 0x0f) == 0x0f
        )
      when 0x16 # LD D, d8
        @d.value = read_byte_and_advance_pc
      when 0x17 # RLA
        cflag = @a.value[7] == 1
        @a.value = (@a.value << 1) | bool_to_integer(flags[:c])
        update_flags(
          z: false,
          n: false,
          h: false,
          c: cflag
        )
      when 0x18 # JR r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        @pc += byte
      when 0x19 # ADD HL, DE
        hflag = (hl & 0x0fff) + (de & 0x0fff) > 0x0fff
        cflag = hl + de > 0xffff
        self.hl = hl + de
        update_flags(
          n: false,
          h: hflag,
          c: cflag
        )
      when 0x1a # LD A, (DE)
        @a.value = read_byte(de)
      when 0x1b # DEC DE
        self.de = de - 1
      when 0x1c # INC E
        @e.increment
        update_flags(
          z: @e.value.zero?,
          n: false,
          h: (@e.value & 0x0f).zero?
        )
      when 0x1d # DEC E
        @e.decrement
        update_flags(
          z: @e.value.zero?,
          n: true,
          h: (@e.value & 0x0f) == 0x0f
        )
      when 0x1e # LD E, d8
        @e.value = read_byte_and_advance_pc
      when 0x1f # RRA
        cflag = @a.value[0] == 1
        @a.value = (@a.value >> 1) | (bool_to_integer(flags[:c]) << 7)
        update_flags(
          z: false,
          n: false,
          h: false,
          c: cflag
        )
      when 0x20 # JR NZ, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        unless flags[:z]
          @pc += byte
          branched = true
        end
      when 0x21 # LD HL, nn
        self.hl = read_word_and_advance_pc
      when 0x22 # LD (HL+), A
        write_byte(hl, @a.value)
        self.hl = hl + 1
      when 0x23 # INC HL
        self.hl = hl + 1
      when 0x24 # INC H
        @h.increment
        update_flags(
          z: @h.value.zero?,
          n: false,
          h: (@h.value & 0x0f).zero?
        )
      when 0x25 # DEC H
        @h.decrement
        update_flags(
          z: @h.value.zero?,
          n: true,
          h: (@h.value & 0x0f) == 0x0f
        )
      when 0x26 # LD H, d8
        @h.value = read_byte_and_advance_pc
      when 0x27 # DAA
        if flags[:n]
          @a.value -= 0x06 if flags[:h]
          @a.value -= 0x60 if flags[:c]
        else
          if flags[:c] || @a.value > 0x99
            @a.value += 0x60
            update_flags(c: true)
          end
          @a.value += 0x06 if flags[:h] || (@a.value & 0x0f) > 0x09
        end
        update_flags(
          z: @a.value.zero?,
          h: false
        )
      when 0x28 # JR Z, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        if flags[:z]
          @pc += byte
          branched = true
        end
      when 0x29 # ADD HL, HL
        hflag = (hl & 0x0fff) + (hl & 0x0fff) > 0x0fff
        cflag = hl + hl > 0xffff
        self.hl = hl + hl
        update_flags(
          n: false,
          h: hflag,
          c: cflag
        )
      when 0x2a # LD A, (HL+)
        @a.value = read_byte(hl)
        self.hl = hl + 1
      when 0x2b # DEC HL
        self.hl = hl - 1
      when 0x2c # INC L
        @l.increment
        update_flags(
          z: @l.value.zero?,
          n: false,
          h: (@l.value & 0x0f).zero?
        )
      when 0x2d # DEC L
        @l.decrement
        update_flags(
          z: @l.value.zero?,
          n: true,
          h: (@l.value & 0x0f) == 0x0f
        )
      when 0x2e # LD L, d8
        @l.value = read_byte_and_advance_pc
      when 0x2f # CPL
        @a.value = ~@a.value
        update_flags(
          n: true,
          h: true
        )
      when 0x30 # JR NC, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        unless flags[:c]
          @pc += byte
          branched = true
        end
      when 0x31 # LD SP, nn
        @sp = read_word_and_advance_pc
      when 0x32 # LD (HL-), A
        write_byte(hl, @a.value)
        self.hl = hl - 1
      when 0x33 # INC SP
        @sp = (@sp + 1) & 0xffff
      when 0x34 # INC (HL)
        byte = read_byte(hl)
        byte = (byte + 1) & 0xff
        write_byte(hl, byte)
        update_flags(
          z: byte.zero?,
          n: false,
          h: (byte & 0x0f).zero?
        )
      when 0x35 # DEC (HL)
        byte = read_byte(hl)
        byte = (byte - 1) & 0xff
        write_byte(hl, byte)
        update_flags(
          z: byte.zero?,
          n: true,
          h: (byte & 0x0f) == 0x0f
        )
      when 0x36 # LD (HL), d8
        byte = read_byte_and_advance_pc
        write_byte(hl, byte)
      when 0x37 # SCF
        update_flags(
          n: false,
          h: false,
          c: true
        )
      when 0x38 # JR C, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)
        if flags[:c]
          @pc += byte
          branched = true
        end
      when 0x39 # ADD HL, SP
        hflag = (hl & 0x0fff) + (@sp & 0x0fff) > 0x0fff
        cflag = hl + @sp > 0xffff
        self.hl = hl + @sp
        update_flags(
          n: false,
          h: hflag,
          c: cflag
        )
      when 0x3a # LD A, (HL-)
        @a.value = read_byte(hl)
        self.hl = hl - 1
      when 0x3b # DEC SP
        @sp = (@sp - 1) & 0xffff
      when 0x3c # INC A
        @a.increment
        update_flags(
          z: @a.value.zero?,
          n: false,
          h: (@a.value & 0x0f).zero?
        )
      when 0x3d # DEC A
        @a.decrement
        update_flags(
          z: @a.value.zero?,
          n: true,
          h: (@a.value & 0x0f) == 0x0f
        )
      when 0x3e # LD A, d8
        @a.value = read_byte_and_advance_pc
      when 0x3f # CCF
        update_flags(
          n: false,
          h: false,
          c: !flags[:c]
        )
      when 0x40 # LD B, B
        @b.value = @b.value
      when 0x41 # LD B, C
        @b.value = @c.value
      when 0x42 # LD B, D
        @b.value = @d.value
      when 0x43 # LD B, E
        @b.value = @e.value
      when 0x44 # LD B, H
        @b.value = @h.value
      when 0x45 # LD B, L
        @b.value = @l.value
      when 0x46 # LD B, (HL)
        @b.value = read_byte(hl)
      when 0x47 # LD B, A
        @b.value = @a.value
      when 0x48 # LD C, B
        @c.value = @b.value
      when 0x49 # LD C, C
        @c.value = @c.value
      when 0x4a # LD C, D
        @c.value = @d.value
      when 0x4b # LD C, E
        @c.value = @e.value
      when 0x4c # LD C, H
        @c.value = @h.value
      when 0x4d # LD C, L
        @c.value = @l.value
      when 0x4e # LD C, (HL)
        @c.value = read_byte(hl)
      when 0x4f # LD C, A
        @c.value = @a.value
      when 0x50 # LD D, B
        @d.value = @b.value
      when 0x51 # LD D, C
        @d.value = @c.value
      when 0x52 # LD D, D
        @d.value = @d.value
      when 0x53 # LD D, E
        @d.value = @e.value
      when 0x54 # LD D, H
        @d.value = @h.value
      when 0x55 # LD D, L
        @d.value = @l.value
      when 0x56 # LD D, (HL)
        @d.value = read_byte(hl)
      when 0x57 # LD D, A
        @d.value = @a.value
      when 0x58 # LD E, B
        @e.value = @b.value
      when 0x59 # LD E, C
        @e.value = @c.value
      when 0x5a # LD E, D
        @e.value = @d.value
      when 0x5b # LD E, E
        @e.value = @e.value
      when 0x5c # LD E, H
        @e.value = @h.value
      when 0x5d # LD E, L
        @e.value = @l.value
      when 0x5e # LD E, (HL)
        @e.value = read_byte(hl)
      when 0x5f # LD E, A
        @e.value = @a.value
      when 0x60 # LD H, B
        @h.value = @b.value
      when 0x61 # LD H, C
        @h.value = @c.value
      when 0x62 # LD H, D
        @h.value = @d.value
      when 0x63 # LD H, E
        @h.value = @e.value
      when 0x64 # LD H, H
        @h.value = @h.value
      when 0x65 # LD H, L
        @h.value = @l.value
      when 0x66 # LD H, (HL)
        @h.value = read_byte(hl)
      when 0x67 # LD H, A
        @h.value = @a.value
      when 0x68 # LD L, B
        @l.value = @b.value
      when 0x69 # LD L, C
        @l.value = @c.value
      when 0x6a # LD L, D
        @l.value = @d.value
      when 0x6b # LD L, E
        @l.value = @e.value
      when 0x6c # LD L, H
        @l.value = @h.value
      when 0x6d # LD L, L
        @l.value = @l.value
      when 0x6e # LD L, (HL)
        @l.value = read_byte(hl)
      when 0x6f # LD L, A
        @l.value = @a.value
      when 0x70 # LD (HL), B
        write_byte(hl, @b.value)
      when 0x71 # LD (HL), C
        write_byte(hl, @c.value)
      when 0x72 # LD (HL), D
        write_byte(hl, @d.value)
      when 0x73 # LD (HL), E
        write_byte(hl, @e.value)
      when 0x74 # LD (HL), H
        write_byte(hl, @h.value)
      when 0x75 # LD (HL), L
        write_byte(hl, @l.value)
      when 0x76 # HALT
        @halted = true
      when 0x77 # LD (HL), A
        write_byte(hl, @a.value)
      when 0x78 # LD A, B
        @a.value = @b.value
      when 0x79 # LD A, C
        @a.value = @c.value
      when 0x7a # LD A, D
        @a.value = @d.value
      when 0x7b # LD A, E
        @a.value = @e.value
      when 0x7c # LD A, H
        @a.value = @h.value
      when 0x7d # LD A, L
        @a.value = @l.value
      when 0x7e # LD A, (HL)
        @a.value = read_byte(hl)
      when 0x7f # LD A, A
        @a.value = @a.value
      when 0x80 # ADD A, B
        add8(@a, @b)
      when 0x81 # ADD A, C
        add8(@a, @c)
      when 0x82 # ADD A, D
        add8(@a, @d)
      when 0x83 # ADD A, E
        add8(@a, @e)
      when 0x84 # ADD A, H
        add8(@a, @h)
      when 0x85 # ADD A, L
        add8(@a, @l)
      when 0x86 # ADD A, (HL)
        add8(@a, Register.new(name: 'HL', value: read_byte(hl)))
      when 0x87 # ADD A, A
        add8(@a, @a)
      when 0x88 # ADC A, B
        adc8(@a, @b)
      when 0x89 # ADC A, C
        adc8(@a, @c)
      when 0x8a # ADC A, D
        adc8(@a, @d)
      when 0x8b # ADC A, E
        adc8(@a, @e)
      when 0x8c # ADC A, H
        adc8(@a, @h)
      when 0x8d # ADC A, L
        adc8(@a, @l)
      when 0x8e # ADC A, (HL)
        adc8(@a, Register.new(name: 'HL', value: read_byte(hl)))
      when 0x8f # ADC A, A
        adc8(@a, @a)
      when 0x90 # SUB B
        sub8(@b)
      when 0x91 # SUB C
        sub8(@c)
      when 0x92 # SUB D
        sub8(@d)
      when 0x93 # SUB E
        sub8(@e)
      when 0x94 # SUB H
        sub8(@h)
      when 0x95 # SUB L
        sub8(@l)
      when 0x96 # SUB (HL)
        sub8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0x97 # SUB A
        sub8(@a)
      when 0x98 # SBC A, B
        sbc8(@b)
      when 0x99 # SBC A, C
        sbc8(@c)
      when 0x9a # SBC A, D
        sbc8(@d)
      when 0x9b # SBC A, E
        sbc8(@e)
      when 0x9c # SBC A, H
        sbc8(@h)
      when 0x9d # SBC A, L
        sbc8(@l)
      when 0x9e # SBC A, (HL)
        sbc8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0x9f # SBC A, A
        sbc8(@a)
      when 0xa0 # AND B
        and8(@b)
      when 0xa1 # AND C
        and8(@c)
      when 0xa2 # AND D
        and8(@d)
      when 0xa3 # AND E
        and8(@e)
      when 0xa4 # AND H
        and8(@h)
      when 0xa5 # AND L
        and8(@l)
      when 0xa6 # AND (HL)
        and8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0xa7 # AND A
        and8(@a)
      when 0xa8 # XOR B
        xor8(@b)
      when 0xa9 # XOR C
        xor8(@c)
      when 0xaa # XOR D
        xor8(@d)
      when 0xab # XOR E
        xor8(@e)
      when 0xac # XOR H
        xor8(@h)
      when 0xad # XOR L
        xor8(@l)
      when 0xae # XOR (HL)
        xor8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0xaf # XOR A
        xor8(@a)
      when 0xb0 # OR B
        or8(@b)
      when 0xb1 # OR C
        or8(@c)
      when 0xb2 # OR D
        or8(@d)
      when 0xb3 # OR E
        or8(@e)
      when 0xb4 # OR H
        or8(@h)
      when 0xb5 # OR L
        or8(@l)
      when 0xb6 # OR (HL)
        or8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0xb7 # OR A
        or8(@a)
      when 0xb8 # CP B
        cp8(@b)
      when 0xb9 # CP C
        cp8(@c)
      when 0xba # CP D
        cp8(@d)
      when 0xbb # CP E
        cp8(@e)
      when 0xbc # CP H
        cp8(@h)
      when 0xbd # CP L
        cp8(@l)
      when 0xbe # CP (HL)
        cp8(Register.new(name: 'HL', value: read_byte(hl)))
      when 0xbf # CP A
        cp8(@a)
      when 0xc0 # RET NZ
        unless flags[:z]
          @pc = read_word(@sp)
          @sp += 2
          branched = true
        end
      when 0xc1 # POP BC
        self.bc = read_word(@sp)
        @sp += 2
      when 0xc2 # JP NZ, nn
        word = read_word_and_advance_pc
        unless flags[:z]
          @pc = word
          branched = true
        end
      when 0xc3 # JP nn
        @pc = read_word_and_advance_pc
      when 0xc4 # CALL NZ, nn
        word = read_word_and_advance_pc
        unless flags[:z]
          @sp -= 2
          write_word(@sp, @pc)
          @pc = word
          branched = true
        end
      when 0xc5 # PUSH BC
        @sp -= 2
        write_word(@sp, bc)
      when 0xc6 # ADD A, d8
        byte = read_byte_and_advance_pc
        add8(@a, Register.new(name: 'd8', value: byte))
      when 0xc7 # RST 00H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x00
      when 0xc8 # RET Z
        if flags[:z]
          @pc = read_word(@sp)
          @sp += 2
          branched = true
        end
      when 0xc9 # RET
        @pc = read_word(@sp)
        @sp += 2
      when 0xca # JP Z, nn
        word = read_word_and_advance_pc
        if flags[:z]
          @pc = word
          branched = true
        end
      when 0xcc # CALL Z, nn
        word = read_word_and_advance_pc
        if flags[:z]
          @sp -= 2
          write_word(@sp, @pc)
          @pc = word
          branched = true
        end
      when 0xcd # CALL nn
        word = read_word_and_advance_pc
        @sp -= 2
        write_word(@sp, @pc)
        @pc = word
      when 0xce # ADC A, d8
        byte = read_byte_and_advance_pc
        adc8(@a, Register.new(name: 'd8', value: byte))
      when 0xcf # RST 08H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x08
      when 0xd0 # RET NC
        unless flags[:c]
          @pc = read_word(@sp)
          @sp += 2
          branched = true
        end
      when 0xd1 # POP DE
        self.de = read_word(@sp)
        @sp += 2
      when 0xd2 # JP NC, nn
        word = read_word_and_advance_pc
        unless flags[:c]
          @pc = word
          branched = true
        end
      when 0xd4 # CALL NC, nn
        word = read_word_and_advance_pc
        unless flags[:c]
          @sp -= 2
          write_word(@sp, @pc)
          @pc = word
          branched = true
        end
      when 0xd5 # PUSH DE
        @sp -= 2
        write_word(@sp, de)
      when 0xd6 # SUB d8
        byte = read_byte_and_advance_pc
        sub8(Register.new(name: 'd8', value: byte))
      when 0xd7 # RST 10H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x10
      when 0xd8 # RET C
        if flags[:c]
          @pc = read_word(@sp)
          @sp += 2
          branched = true
        end
      when 0xd9 # RETI
        @pc = read_word(@sp)
        @sp += 2
        @ime = true
      when 0xda # JP C, nn
        word = read_word_and_advance_pc
        if flags[:c]
          @pc = word
          branched = true
        end
      when 0xdc # CALL C, nn
        word = read_word_and_advance_pc
        if flags[:c]
          @sp -= 2
          write_word(@sp, @pc)
          @pc = word
          branched = true
        end
      when 0xde # SBC A, d8
        byte = read_byte_and_advance_pc
        sbc8(Register.new(name: 'd8', value: byte))
      when 0xdf # RST 18H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x18
      when 0xe0 # LDH (a8), A
        byte = read_byte_and_advance_pc
        write_byte(0xff00 + byte, @a.value)
      when 0xe1 # POP HL
        self.hl = read_word(@sp)
        @sp += 2
      when 0xe2 # LD (C), A
        write_byte(0xff00 + @c.value, @a.value)
      when 0xe5 # PUSH HL
        @sp -= 2
        write_word(@sp, hl)
      when 0xe6 # AND d8
        byte = read_byte_and_advance_pc
        and8(Register.new(name: 'd8', value: byte))
      when 0xe7 # RST 20H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x20
      when 0xe8 # ADD SP, r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)

        hflag = (@sp & 0x0f) + (byte & 0x0f) > 0x0f
        cflag = (@sp & 0xff) + (byte & 0xff) > 0xff

        @sp += byte
        @sp &= 0xffff
        update_flags(
          z: false,
          n: false,
          h: hflag,
          c: cflag
        )
      when 0xe9 # JP (HL)
        @pc = hl
      when 0xea # LD (nn), A
        word = read_word_and_advance_pc
        write_byte(word, @a.value)
      when 0xee # XOR d8
        byte = read_byte_and_advance_pc
        xor8(Register.new(name: 'd8', value: byte))
      when 0xef # RST 28H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x28
      when 0xf0 # LDH A, (a8)
        byte = read_byte_and_advance_pc
        @a.value = read_byte(0xff00 + byte)
      when 0xf1 # POP AF
        self.af = read_word(@sp)
        @sp += 2
      when 0xf2 # LD A, (C)
        @a.value = read_byte(0xff00 + @c.value)
      when 0xf3 # DI
        @ime_delay = false
        @ime = false
      when 0xf5 # PUSH AF
        @sp -= 2
        write_word(@sp, af)
      when 0xf6 # OR d8
        byte = read_byte_and_advance_pc
        or8(Register.new(name: 'd8', value: byte))
      when 0xf7 # RST 30H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x30
      when 0xf8 # LD HL, SP+r8
        byte = convert_to_twos_complement(read_byte_and_advance_pc)

        hflag = (@sp & 0x0f) + (byte & 0x0f) > 0x0f
        cflag = (@sp & 0xff) + (byte & 0xff) > 0xff
        self.hl = @sp + byte
        update_flags(
          z: false,
          n: false,
          h: hflag,
          c: cflag
        )
      when 0xf9 # LD SP, HL
        @sp = hl
      when 0xfa # LD A, (nn)
        word = read_word_and_advance_pc
        @a.value = read_byte(word)
      when 0xfb # EI
        @ime_delay = true
      when 0xfe # CP d8
        byte = read_byte_and_advance_pc
        update_flags(
          z: @a.value == byte,
          n: true,
          h: (@a.value & 0x0f) < (byte & 0x0f),
          c: @a.value < byte
        )
      when 0xff # RST 38H
        @sp -= 2
        write_word(@sp, @pc)
        @pc = 0x38
      when 0xcb # CB prefix
        opcode = read_byte_and_advance_pc
        cbprefixed = true

        # p "CB #{opcode.to_s(16)}"

        case opcode
        when 0x00 # RLC B
          rlc8(@b)
        when 0x01 # RLC C
          rlc8(@c)
        when 0x02 # RLC D
          rlc8(@d)
        when 0x03 # RLC E
          rlc8(@e)
        when 0x04 # RLC H
          rlc8(@h)
        when 0x05 # RLC L
          rlc8(@l)
        when 0x06 # RLC (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          rlc8(reg)
          write_byte(hl, reg.value)
        when 0x07 # RLC A
          rlc8(@a)
        when 0x08 # RRC B
          rrc8(@b)
        when 0x09 # RRC C
          rrc8(@c)
        when 0x0a # RRC D
          rrc8(@d)
        when 0x0b # RRC E
          rrc8(@e)
        when 0x0c # RRC H
          rrc8(@h)
        when 0x0d # RRC L
          rrc8(@l)
        when 0x0e # RRC (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          rrc8(reg)
          write_byte(hl, reg.value)
        when 0x0f # RRC A
          rrc8(@a)
        when 0x10 # RL B
          rl8(@b)
        when 0x11 # RL C
          rl8(@c)
        when 0x12 # RL D
          rl8(@d)
        when 0x13 # RL E
          rl8(@e)
        when 0x14 # RL H
          rl8(@h)
        when 0x15 # RL L
          rl8(@l)
        when 0x16 # RL (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          rl8(reg)
          write_byte(hl, reg.value)
        when 0x17 # RL A
          rl8(@a)
        when 0x18 # RR B
          rr8(@b)
        when 0x19 # RR C
          rr8(@c)
        when 0x1a # RR D
          rr8(@d)
        when 0x1b # RR E
          rr8(@e)
        when 0x1c # RR H
          rr8(@h)
        when 0x1d # RR L
          rr8(@l)
        when 0x1e # RR (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          rr8(reg)
          write_byte(hl, reg.value)
        when 0x1f # RR A
          rr8(@a)
        when 0x20 # SLA B
          sla8(@b)
        when 0x21 # SLA C
          sla8(@c)
        when 0x22 # SLA D
          sla8(@d)
        when 0x23 # SLA E
          sla8(@e)
        when 0x24 # SLA H
          sla8(@h)
        when 0x25 # SLA L
          sla8(@l)
        when 0x26 # SLA (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          sla8(reg)
          write_byte(hl, reg.value)
        when 0x27 # SLA A
          sla8(@a)
        when 0x28 # SRA B
          sra8(@b)
        when 0x29 # SRA C
          sra8(@c)
        when 0x2a # SRA D
          sra8(@d)
        when 0x2b # SRA E
          sra8(@e)
        when 0x2c # SRA H
          sra8(@h)
        when 0x2d # SRA L
          sra8(@l)
        when 0x2e # SRA (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          sra8(reg)
          write_byte(hl, reg.value)
        when 0x2f # SRA A
          sra8(@a)
        when 0x30 # SWAP B
          swap8(@b)
        when 0x31 # SWAP C
          swap8(@c)
        when 0x32 # SWAP D
          swap8(@d)
        when 0x33 # SWAP E
          swap8(@e)
        when 0x34 # SWAP H
          swap8(@h)
        when 0x35 # SWAP L
          swap8(@l)
        when 0x36 # SWAP (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          swap8(reg)
          write_byte(hl, reg.value)
        when 0x37 # SWAP A
          swap8(@a)
        when 0x38 # SRL B
          srl8(@b)
        when 0x39 # SRL C
          srl8(@c)
        when 0x3a # SRL D
          srl8(@d)
        when 0x3b # SRL E
          srl8(@e)
        when 0x3c # SRL H
          srl8(@h)
        when 0x3d # SRL L
          srl8(@l)
        when 0x3e # SRL (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          srl8(reg)
          write_byte(hl, reg.value)
        when 0x3f # SRL A
          srl8(@a)
        when 0x40 # BIT 0, B
          bit8(0, @b)
        when 0x41 # BIT 0, C
          bit8(0, @c)
        when 0x42 # BIT 0, D
          bit8(0, @d)
        when 0x43 # BIT 0, E
          bit8(0, @e)
        when 0x44 # BIT 0, H
          bit8(0, @h)
        when 0x45 # BIT 0, L
          bit8(0, @l)
        when 0x46 # BIT 0, (HL)
          bit8(0, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x47 # BIT 0, A
          bit8(0, @a)
        when 0x48 # BIT 1, B
          bit8(1, @b)
        when 0x49 # BIT 1, C
          bit8(1, @c)
        when 0x4a # BIT 1, D
          bit8(1, @d)
        when 0x4b # BIT 1, E
          bit8(1, @e)
        when 0x4c # BIT 1, H
          bit8(1, @h)
        when 0x4d # BIT 1, L
          bit8(1, @l)
        when 0x4e # BIT 1, (HL)
          bit8(1, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x4f # BIT 1, A
          bit8(1, @a)
        when 0x50 # BIT 2, B
          bit8(2, @b)
        when 0x51 # BIT 2, C
          bit8(2, @c)
        when 0x52 # BIT 2, D
          bit8(2, @d)
        when 0x53 # BIT 2, E
          bit8(2, @e)
        when 0x54 # BIT 2, H
          bit8(2, @h)
        when 0x55 # BIT 2, L
          bit8(2, @l)
        when 0x56 # BIT 2, (HL)
          bit8(2, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x57 # BIT 2, A
          bit8(2, @a)
        when 0x58 # BIT 3, B
          bit8(3, @b)
        when 0x59 # BIT 3, C
          bit8(3, @c)
        when 0x5a # BIT 3, D
          bit8(3, @d)
        when 0x5b # BIT 3, E
          bit8(3, @e)
        when 0x5c # BIT 3, H
          bit8(3, @h)
        when 0x5d # BIT 3, L
          bit8(3, @l)
        when 0x5e # BIT 3, (HL)
          bit8(3, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x5f # BIT 3, A
          bit8(3, @a)
        when 0x60 # BIT 4, B
          bit8(4, @b)
        when 0x61 # BIT 4, C
          bit8(4, @c)
        when 0x62 # BIT 4, D
          bit8(4, @d)
        when 0x63 # BIT 4, E
          bit8(4, @e)
        when 0x64 # BIT 4, H
          bit8(4, @h)
        when 0x65 # BIT 4, L
          bit8(4, @l)
        when 0x66 # BIT 4, (HL)
          bit8(4, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x67 # BIT 4, A
          bit8(4, @a)
        when 0x68 # BIT 5, B
          bit8(5, @b)
        when 0x69 # BIT 5, C
          bit8(5, @c)
        when 0x6a # BIT 5, D
          bit8(5, @d)
        when 0x6b # BIT 5, E
          bit8(5, @e)
        when 0x6c # BIT 5, H
          bit8(5, @h)
        when 0x6d # BIT 5, L
          bit8(5, @l)
        when 0x6e # BIT 5, (HL)
          bit8(5, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x6f # BIT 5, A
          bit8(5, @a)
        when 0x70 # BIT 6, B
          bit8(6, @b)
        when 0x71 # BIT 6, C
          bit8(6, @c)
        when 0x72 # BIT 6, D
          bit8(6, @d)
        when 0x73 # BIT 6, E
          bit8(6, @e)
        when 0x74 # BIT 6, H
          bit8(6, @h)
        when 0x75 # BIT 6, L
          bit8(6, @l)
        when 0x76 # BIT 6, (HL)
          bit8(6, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x77 # BIT 6, A
          bit8(6, @a)
        when 0x78 # BIT 7, B
          bit8(7, @b)
        when 0x79 # BIT 7, C
          bit8(7, @c)
        when 0x7a # BIT 7, D
          bit8(7, @d)
        when 0x7b # BIT 7, E
          bit8(7, @e)
        when 0x7c # BIT 7, H
          bit8(7, @h)
        when 0x7d # BIT 7, L
          bit8(7, @l)
        when 0x7e # BIT 7, (HL)
          bit8(7, Register.new(name: 'HL', value: read_byte(hl)))
        when 0x7f # BIT 7, A
          bit8(7, @a)
        when 0x80 # RES 0, B
          res8(0, @b)
        when 0x81 # RES 0, C
          res8(0, @c)
        when 0x82 # RES 0, D
          res8(0, @d)
        when 0x83 # RES 0, E
          res8(0, @e)
        when 0x84 # RES 0, H
          res8(0, @h)
        when 0x85 # RES 0, L
          res8(0, @l)
        when 0x86 # RES 0, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(0, reg)
          write_byte(hl, reg.value)
        when 0x87 # RES 0, A
          res8(0, @a)
        when 0x88 # RES 1, B
          res8(1, @b)
        when 0x89 # RES 1, C
          res8(1, @c)
        when 0x8a # RES 1, D
          res8(1, @d)
        when 0x8b # RES 1, E
          res8(1, @e)
        when 0x8c # RES 1, H
          res8(1, @h)
        when 0x8d # RES 1, L
          res8(1, @l)
        when 0x8e # RES 1, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(1, reg)
          write_byte(hl, reg.value)
        when 0x8f # RES 1, A
          res8(1, @a)
        when 0x90 # RES 2, B
          res8(2, @b)
        when 0x91 # RES 2, C
          res8(2, @c)
        when 0x92 # RES 2, D
          res8(2, @d)
        when 0x93 # RES 2, E
          res8(2, @e)
        when 0x94 # RES 2, H
          res8(2, @h)
        when 0x95 # RES 2, L
          res8(2, @l)
        when 0x96 # RES 2, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(2, reg)
          write_byte(hl, reg.value)
        when 0x97 # RES 2, A
          res8(2, @a)
        when 0x98 # RES 3, B
          res8(3, @b)
        when 0x99 # RES 3, C
          res8(3, @c)
        when 0x9a # RES 3, D
          res8(3, @d)
        when 0x9b # RES 3, E
          res8(3, @e)
        when 0x9c # RES 3, H
          res8(3, @h)
        when 0x9d # RES 3, L
          res8(3, @l)
        when 0x9e # RES 3, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(3, reg)
          write_byte(hl, reg.value)
        when 0x9f # RES 3, A
          res8(3, @a)
        when 0xa0 # RES 4, B
          res8(4, @b)
        when 0xa1 # RES 4, C
          res8(4, @c)
        when 0xa2 # RES 4, D
          res8(4, @d)
        when 0xa3 # RES 4, E
          res8(4, @e)
        when 0xa4 # RES 4, H
          res8(4, @h)
        when 0xa5 # RES 4, L
          res8(4, @l)
        when 0xa6 # RES 4, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(4, reg)
          write_byte(hl, reg.value)
        when 0xa7 # RES 4, A
          res8(4, @a)
        when 0xa8 # RES 5, B
          res8(5, @b)
        when 0xa9 # RES 5, C
          res8(5, @c)
        when 0xaa # RES 5, D
          res8(5, @d)
        when 0xab # RES 5, E
          res8(5, @e)
        when 0xac # RES 5, H
          res8(5, @h)
        when 0xad # RES 5, L
          res8(5, @l)
        when 0xae # RES 5, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(5, reg)
          write_byte(hl, reg.value)
        when 0xaf # RES 5, A
          res8(5, @a)
        when 0xb0 # RES 6, B
          res8(6, @b)
        when 0xb1 # RES 6, C
          res8(6, @c)
        when 0xb2 # RES 6, D
          res8(6, @d)
        when 0xb3 # RES 6, E
          res8(6, @e)
        when 0xb4 # RES 6, H
          res8(6, @h)
        when 0xb5 # RES 6, L
          res8(6, @l)
        when 0xb6 # RES 6, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(6, reg)
          write_byte(hl, reg.value)
        when 0xb7 # RES 6, A
          res8(6, @a)
        when 0xb8 # RES 7, B
          res8(7, @b)
        when 0xb9 # RES 7, C
          res8(7, @c)
        when 0xba # RES 7, D
          res8(7, @d)
        when 0xbb # RES 7, E
          res8(7, @e)
        when 0xbc # RES 7, H
          res8(7, @h)
        when 0xbd # RES 7, L
          res8(7, @l)
        when 0xbe # RES 7, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          res8(7, reg)
          write_byte(hl, reg.value)
        when 0xbf # RES 7, A
          res8(7, @a)
        when 0xc0 # SET 0, B
          set8(0, @b)
        when 0xc1 # SET 0, C
          set8(0, @c)
        when 0xc2 # SET 0, D
          set8(0, @d)
        when 0xc3 # SET 0, E
          set8(0, @e)
        when 0xc4 # SET 0, H
          set8(0, @h)
        when 0xc5 # SET 0, L
          set8(0, @l)
        when 0xc6 # SET 0, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(0, reg)
          write_byte(hl, reg.value)
        when 0xc7 # SET 0, A
          set8(0, @a)
        when 0xc8 # SET 1, B
          set8(1, @b)
        when 0xc9 # SET 1, C
          set8(1, @c)
        when 0xca # SET 1, D
          set8(1, @d)
        when 0xcb # SET 1, E
          set8(1, @e)
        when 0xcc # SET 1, H
          set8(1, @h)
        when 0xcd # SET 1, L
          set8(1, @l)
        when 0xce # SET 1, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(1, reg)
          write_byte(hl, reg.value)
        when 0xcf # SET 1, A
          set8(1, @a)
        when 0xd0 # SET 2, B
          set8(2, @b)
        when 0xd1 # SET 2, C
          set8(2, @c)
        when 0xd2 # SET 2, D
          set8(2, @d)
        when 0xd3 # SET 2, E
          set8(2, @e)
        when 0xd4 # SET 2, H
          set8(2, @h)
        when 0xd5 # SET 2, L
          set8(2, @l)
        when 0xd6 # SET 2, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(2, reg)
          write_byte(hl, reg.value)
        when 0xd7 # SET 2, A
          set8(2, @a)
        when 0xd8 # SET 3, B
          set8(3, @b)
        when 0xd9 # SET 3, C
          set8(3, @c)
        when 0xda # SET 3, D
          set8(3, @d)
        when 0xdb # SET 3, E
          set8(3, @e)
        when 0xdc # SET 3, H
          set8(3, @h)
        when 0xdd # SET 3, L
          set8(3, @l)
        when 0xde # SET 3, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(3, reg)
          write_byte(hl, reg.value)
        when 0xdf # SET 3, A
          set8(3, @a)
        when 0xe0 # SET 4, B
          set8(4, @b)
        when 0xe1 # SET 4, C
          set8(4, @c)
        when 0xe2 # SET 4, D
          set8(4, @d)
        when 0xe3 # SET 4, E
          set8(4, @e)
        when 0xe4 # SET 4, H
          set8(4, @h)
        when 0xe5 # SET 4, L
          set8(4, @l)
        when 0xe6 # SET 4, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(4, reg)
          write_byte(hl, reg.value)
        when 0xe7 # SET 4, A
          set8(4, @a)
        when 0xe8 # SET 5, B
          set8(5, @b)
        when 0xe9 # SET 5, C
          set8(5, @c)
        when 0xea # SET 5, D
          set8(5, @d)
        when 0xeb # SET 5, E
          set8(5, @e)
        when 0xec # SET 5, H
          set8(5, @h)
        when 0xed # SET 5, L
          set8(5, @l)
        when 0xee # SET 5, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(5, reg)
          write_byte(hl, reg.value)
        when 0xef # SET 5, A
          set8(5, @a)
        when 0xf0 # SET 6, B
          set8(6, @b)
        when 0xf1 # SET 6, C
          set8(6, @c)
        when 0xf2 # SET 6, D
          set8(6, @d)
        when 0xf3 # SET 6, E
          set8(6, @e)
        when 0xf4 # SET 6, H
          set8(6, @h)
        when 0xf5 # SET 6, L
          set8(6, @l)
        when 0xf6 # SET 6, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(6, reg)
          write_byte(hl, reg.value)
        when 0xf7 # SET 6, A
          set8(6, @a)
        when 0xf8 # SET 7, B
          set8(7, @b)
        when 0xf9 # SET 7, C
          set8(7, @c)
        when 0xfa # SET 7, D
          set8(7, @d)
        when 0xfb # SET 7, E
          set8(7, @e)
        when 0xfc then set8(7, @h)
        when 0xfd then set8(7, @l)
        when 0xfe # SET 7, (HL)
          reg = Register.new(name: 'HL', value: read_byte(hl))
          set8(7, reg)
          write_byte(hl, reg.value)
        when 0xff then set8(7, @a) # SET 7, A
        else
          raise "unknown opcode: 0xcb 0x#{'%02x' % opcode}"
        end
      else
        raise "unknown opcode: 0x#{'%02x' % opcode}"
      end

      @sp &= 0xffff

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
      puts "OP: 0x#{'%02x' % opcode}, PC: 0x#{'%04x' % @pc}, SP: 0x#{'%04x' % @sp}, A: 0x#{'%02x' % @a.value}, B: 0x#{'%02x' % @b.value}, C: 0x#{'%02x' % @c.value}, D: 0x#{'%02x' % @d.value}, E: 0x#{'%02x' % @e.value}, H: 0x#{'%02x' % @h.value}, L: 0x#{'%02x' % @l.value}, F: 0x#{'%02x' % @f.value}"
    end

    def flags
      {
        z: @f.value[7] == 1,
        n: @f.value[6] == 1,
        h: @f.value[5] == 1,
        c: @f.value[4] == 1
      }
    end

    def update_flags(z: flags[:z], n: flags[:n], h: flags[:h], c: flags[:c])
      @f.value = 0x00
      @f.value |= 0x80 if z
      @f.value |= 0x40 if n
      @f.value |= 0x20 if h
      @f.value |= 0x10 if c
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
      byte &= 0xff
      byte > 127 ? byte - 256 : byte
    end

    def ld8(x, y)
      x.value = y.value
    end

    def add8(x, y)
      hflag = (x.value & 0x0f) + (y.value & 0x0f) > 0x0f
      cflag = x.value + y.value > 0xff
      x.value += y.value
      update_flags(
        z: x.value.zero?,
        n: false,
        h: hflag,
        c: cflag
      )
    end

    def adc8(x, y)
      c_value = bool_to_integer(flags[:c])
      hflag = (x.value & 0x0f) + (y.value & 0x0f) + c_value > 0x0f
      cflag = x.value + y.value + c_value > 0xff
      x.value += y.value + c_value
      update_flags(
        z: x.value.zero?,
        n: false,
        h: hflag,
        c: cflag
      )
    end

    def sub8(x)
      hflag = (x.value & 0x0f) > (@a.value & 0x0f)
      cflag = x.value > @a.value
      @a.value -= x.value
      update_flags(
        z: @a.value.zero?,
        n: true,
        h: hflag,
        c: cflag
      )
    end

    def sbc8(x)
      c_value = bool_to_integer(flags[:c])
      hflag = (x.value & 0x0f) + c_value > (@a.value & 0x0f)
      cflag = x.value + c_value > @a.value
      @a.value -= x.value + c_value
      update_flags(
        z: @a.value.zero?,
        n: true,
        h: hflag,
        c: cflag
      )
    end

    def and8(x)
      @a.value &= x.value
      update_flags(
        z: @a.value.zero?,
        n: false,
        h: true,
        c: false
      )
    end

    def or8(x)
      @a.value |= x.value
      update_flags(
        z: @a.value.zero?,
        n: false,
        h: false,
        c: false
      )
    end

    def xor8(x)
      @a.value ^= x.value
      update_flags(
        z: @a.value.zero?,
        n: false,
        h: false,
        c: false
      )
    end

    def cp8(x)
      hflag = (x.value & 0x0f) > (@a.value & 0x0f)
      cflag = x.value > @a.value
      update_flags(
        z: @a.value == x.value,
        n: true,
        h: hflag,
        c: cflag
      )
    end

    def rlc8(x)
      x.value = (x.value << 1) | (x.value >> 7)
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: x.value[0] == 1
      )
    end

    def rrc8(x)
      x.value = (x.value >> 1) | (x.value << 7)
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: x.value[7] == 1
      )
    end

    def rl8(x)
      cflag = x.value[7] == 1
      x.value = (x.value << 1) | bool_to_integer(flags[:c])
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: cflag
      )
    end

    def rr8(x)
      cflag = x.value[0] == 1
      x.value = (x.value >> 1) | (bool_to_integer(flags[:c]) << 7)
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: cflag
      )
    end

    def sla8(x)
      cflag = x.value[7] == 1
      x.value <<= 1
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: cflag
      )
    end

    def sra8(x)
      cflag = x.value[0] == 1
      x.value = (x.value >> 1) | (x.value[7] << 7)
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: cflag
      )
    end

    def swap8(x)
      x.value = ((x.value & 0x0f) << 4) | ((x.value & 0xf0) >> 4)
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: false
      )
    end

    def srl8(x)
      cflag = x.value[0] == 1
      x.value >>= 1
      update_flags(
        z: x.value.zero?,
        n: false,
        h: false,
        c: cflag
      )
    end

    def bit8(n, x)
      update_flags(
        z: x.value[n].zero?,
        n: false,
        h: true
      )
    end

    def set8(n, x)
      x.value |= (1 << n)
    end

    def res8(n, x)
      x.value &= ((~(1 << n)) & 0xff)
    end
  end
end
