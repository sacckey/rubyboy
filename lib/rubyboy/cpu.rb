# frozen_string_literal: true

require_relative 'registers'

module Rubyboy
  class Cpu
    def initialize(bus, interrupt)
      @bus = bus
      @interrupt = interrupt
      @registers = Registers.new

      @pc = 0x0100
      @sp = 0xfffe
      @ime = false
      @ime_delay = false
      @halted = false
    end

    def exec
      opcode = read_byte(@pc)
      # print_log(opcode)

      @halted &= @interrupt.interrupts == 0

      return 16 if @halted

      if @ime && @interrupt.interrupts > 0
        pcs = [0x0040, 0x0048, 0x0050, 0x0058, 0x0060]
        5.times do |i|
          next if @interrupt.interrupts[i] == 0

          @interrupt.reset_flag(i)
          @ime = false
          @sp -= 2
          @bus.write_word(@sp, @pc)
          @pc = pcs[i]

          break
        end

        return 20
      else
        increment_pc
      end

      if @ime_delay
        @ime_delay = false
        @ime = true
      end

      case opcode
      when 0x00 then 4 # NOP
      when 0x01 then ld16(:bc, :immediate16, cycles: 12)
      when 0x02 then ld8(:indirect_bc, :a, cycles: 8)
      when 0x03 then inc16(:bc, cycles: 8)
      when 0x04 then inc8(:b, cycles: 4)
      when 0x05 then dec8(:b, cycles: 4)
      when 0x06 then ld8(:b, :immediate8, cycles: 8)
      when 0x07 then rlca(cycles: 4)
      when 0x08 then ld16(:direct16, :sp, cycles: 20)
      when 0x09 then add16(:hl, :bc, cycles: 8)
      when 0x0a then ld8(:a, :indirect_bc, cycles: 8)
      when 0x0b then dec16(:bc, cycles: 8)
      when 0x0c then inc8(:c, cycles: 4)
      when 0x0d then dec8(:c, cycles: 4)
      when 0x0e then ld8(:c, :immediate8, cycles: 8)
      when 0x0f then rrca(cycles: 4)
      when 0x10 then 4 # STOP
      when 0x11 then ld16(:de, :immediate16, cycles: 12)
      when 0x12 then ld8(:indirect_de, :a, cycles: 8)
      when 0x13 then inc16(:de, cycles: 8)
      when 0x14 then inc8(:d, cycles: 4)
      when 0x15 then dec8(:d, cycles: 4)
      when 0x16 then ld8(:d, :immediate8, cycles: 8)
      when 0x17 then rla(cycles: 4)
      when 0x18 then jr(condition: true)
      when 0x19 then add16(:hl, :de, cycles: 8)
      when 0x1a then ld8(:a, :indirect_de, cycles: 8)
      when 0x1b then dec16(:de, cycles: 8)
      when 0x1c then inc8(:e, cycles: 4)
      when 0x1d then dec8(:e, cycles: 4)
      when 0x1e then ld8(:e, :immediate8, cycles: 8)
      when 0x1f then rra(cycles: 4)
      when 0x20 then jr(condition: !flag_z)
      when 0x21 then ld16(:hl, :immediate16, cycles: 12)
      when 0x22 then ld8(:hl_inc, :a, cycles: 8)
      when 0x23 then inc16(:hl, cycles: 8)
      when 0x24 then inc8(:h, cycles: 4)
      when 0x25 then dec8(:h, cycles: 4)
      when 0x26 then ld8(:h, :immediate8, cycles: 8)
      when 0x27 then daa(cycles: 4)
      when 0x28 then jr(condition: flag_z)
      when 0x29 then add16(:hl, :hl, cycles: 8)
      when 0x2a then ld8(:a, :hl_inc, cycles: 8)
      when 0x2b then dec16(:hl, cycles: 8)
      when 0x2c then inc8(:l, cycles: 4)
      when 0x2d then dec8(:l, cycles: 4)
      when 0x2e then ld8(:l, :immediate8, cycles: 8)
      when 0x2f then cpl(cycles: 4)
      when 0x30 then jr(condition: !flag_c)
      when 0x31 then ld16(:sp, :immediate16, cycles: 12)
      when 0x32 then ld8(:hl_dec, :a, cycles: 8)
      when 0x33 then inc16(:sp, cycles: 8)
      when 0x34 then inc8(:indirect_hl, cycles: 12)
      when 0x35 then dec8(:indirect_hl, cycles: 12)
      when 0x36 then ld8(:indirect_hl, :immediate8, cycles: 12)
      when 0x37 then scf(cycles: 4)
      when 0x38 then jr(condition: flag_c)
      when 0x39 then add16(:hl, :sp, cycles: 8)
      when 0x3a then ld8(:a, :hl_dec, cycles: 8)
      when 0x3b then dec16(:sp, cycles: 8)
      when 0x3c then inc8(:a, cycles: 4)
      when 0x3d then dec8(:a, cycles: 4)
      when 0x3e then ld8(:a, :immediate8, cycles: 8)
      when 0x3f then ccf(cycles: 4)
      when 0x40 then ld8(:b, :b, cycles: 4)
      when 0x41 then ld8(:b, :c, cycles: 4)
      when 0x42 then ld8(:b, :d, cycles: 4)
      when 0x43 then ld8(:b, :e, cycles: 4)
      when 0x44 then ld8(:b, :h, cycles: 4)
      when 0x45 then ld8(:b, :l, cycles: 4)
      when 0x46 then ld8(:b, :indirect_hl, cycles: 8)
      when 0x47 then ld8(:b, :a, cycles: 4)
      when 0x48 then ld8(:c, :b, cycles: 4)
      when 0x49 then ld8(:c, :c, cycles: 4)
      when 0x4a then ld8(:c, :d, cycles: 4)
      when 0x4b then ld8(:c, :e, cycles: 4)
      when 0x4c then ld8(:c, :h, cycles: 4)
      when 0x4d then ld8(:c, :l, cycles: 4)
      when 0x4e then ld8(:c, :indirect_hl, cycles: 8)
      when 0x4f then ld8(:c, :a, cycles: 4)
      when 0x50 then ld8(:d, :b, cycles: 4)
      when 0x51 then ld8(:d, :c, cycles: 4)
      when 0x52 then ld8(:d, :d, cycles: 4)
      when 0x53 then ld8(:d, :e, cycles: 4)
      when 0x54 then ld8(:d, :h, cycles: 4)
      when 0x55 then ld8(:d, :l, cycles: 4)
      when 0x56 then ld8(:d, :indirect_hl, cycles: 8)
      when 0x57 then ld8(:d, :a, cycles: 4)
      when 0x58 then ld8(:e, :b, cycles: 4)
      when 0x59 then ld8(:e, :c, cycles: 4)
      when 0x5a then ld8(:e, :d, cycles: 4)
      when 0x5b then ld8(:e, :e, cycles: 4)
      when 0x5c then ld8(:e, :h, cycles: 4)
      when 0x5d then ld8(:e, :l, cycles: 4)
      when 0x5e then ld8(:e, :indirect_hl, cycles: 8)
      when 0x5f then ld8(:e, :a, cycles: 4)
      when 0x60 then ld8(:h, :b, cycles: 4)
      when 0x61 then ld8(:h, :c, cycles: 4)
      when 0x62 then ld8(:h, :d, cycles: 4)
      when 0x63 then ld8(:h, :e, cycles: 4)
      when 0x64 then ld8(:h, :h, cycles: 4)
      when 0x65 then ld8(:h, :l, cycles: 4)
      when 0x66 then ld8(:h, :indirect_hl, cycles: 8)
      when 0x67 then ld8(:h, :a, cycles: 4)
      when 0x68 then ld8(:l, :b, cycles: 4)
      when 0x69 then ld8(:l, :c, cycles: 4)
      when 0x6a then ld8(:l, :d, cycles: 4)
      when 0x6b then ld8(:l, :e, cycles: 4)
      when 0x6c then ld8(:l, :h, cycles: 4)
      when 0x6d then ld8(:l, :l, cycles: 4)
      when 0x6e then ld8(:l, :indirect_hl, cycles: 8)
      when 0x6f then ld8(:l, :a, cycles: 4)
      when 0x70 then ld8(:indirect_hl, :b, cycles: 8)
      when 0x71 then ld8(:indirect_hl, :c, cycles: 8)
      when 0x72 then ld8(:indirect_hl, :d, cycles: 8)
      when 0x73 then ld8(:indirect_hl, :e, cycles: 8)
      when 0x74 then ld8(:indirect_hl, :h, cycles: 8)
      when 0x75 then ld8(:indirect_hl, :l, cycles: 8)
      when 0x76 then halt(cycles: 4)
      when 0x77 then ld8(:indirect_hl, :a, cycles: 8)
      when 0x78 then ld8(:a, :b, cycles: 4)
      when 0x79 then ld8(:a, :c, cycles: 4)
      when 0x7a then ld8(:a, :d, cycles: 4)
      when 0x7b then ld8(:a, :e, cycles: 4)
      when 0x7c then ld8(:a, :h, cycles: 4)
      when 0x7d then ld8(:a, :l, cycles: 4)
      when 0x7e then ld8(:a, :indirect_hl, cycles: 8)
      when 0x7f then ld8(:a, :a, cycles: 4)
      when 0x80 then add8(:b, cycles: 4)
      when 0x81 then add8(:c, cycles: 4)
      when 0x82 then add8(:d, cycles: 4)
      when 0x83 then add8(:e, cycles: 4)
      when 0x84 then add8(:h, cycles: 4)
      when 0x85 then add8(:l, cycles: 4)
      when 0x86 then add8(:indirect_hl, cycles: 8)
      when 0x87 then add8(:a, cycles: 4)
      when 0x88 then adc8(:b, cycles: 4)
      when 0x89 then adc8(:c, cycles: 4)
      when 0x8a then adc8(:d, cycles: 4)
      when 0x8b then adc8(:e, cycles: 4)
      when 0x8c then adc8(:h, cycles: 4)
      when 0x8d then adc8(:l, cycles: 4)
      when 0x8e then adc8(:indirect_hl, cycles: 8)
      when 0x8f then adc8(:a, cycles: 4)
      when 0x90 then sub8(:b, cycles: 4)
      when 0x91 then sub8(:c, cycles: 4)
      when 0x92 then sub8(:d, cycles: 4)
      when 0x93 then sub8(:e, cycles: 4)
      when 0x94 then sub8(:h, cycles: 4)
      when 0x95 then sub8(:l, cycles: 4)
      when 0x96 then sub8(:indirect_hl, cycles: 8)
      when 0x97 then sub8(:a, cycles: 4)
      when 0x98 then sbc8(:b, cycles: 4)
      when 0x99 then sbc8(:c, cycles: 4)
      when 0x9a then sbc8(:d, cycles: 4)
      when 0x9b then sbc8(:e, cycles: 4)
      when 0x9c then sbc8(:h, cycles: 4)
      when 0x9d then sbc8(:l, cycles: 4)
      when 0x9e then sbc8(:indirect_hl, cycles: 8)
      when 0x9f then sbc8(:a, cycles: 4)
      when 0xa0 then and8(:b, cycles: 4)
      when 0xa1 then and8(:c, cycles: 4)
      when 0xa2 then and8(:d, cycles: 4)
      when 0xa3 then and8(:e, cycles: 4)
      when 0xa4 then and8(:h, cycles: 4)
      when 0xa5 then and8(:l, cycles: 4)
      when 0xa6 then and8(:indirect_hl, cycles: 8)
      when 0xa7 then and8(:a, cycles: 4)
      when 0xa8 then xor8(:b, cycles: 4)
      when 0xa9 then xor8(:c, cycles: 4)
      when 0xaa then xor8(:d, cycles: 4)
      when 0xab then xor8(:e, cycles: 4)
      when 0xac then xor8(:h, cycles: 4)
      when 0xad then xor8(:l, cycles: 4)
      when 0xae then xor8(:indirect_hl, cycles: 8)
      when 0xaf then xor8(:a, cycles: 4)
      when 0xb0 then or8(:b, cycles: 4)
      when 0xb1 then or8(:c, cycles: 4)
      when 0xb2 then or8(:d, cycles: 4)
      when 0xb3 then or8(:e, cycles: 4)
      when 0xb4 then or8(:h, cycles: 4)
      when 0xb5 then or8(:l, cycles: 4)
      when 0xb6 then or8(:indirect_hl, cycles: 8)
      when 0xb7 then or8(:a, cycles: 4)
      when 0xb8 then cp8(:b, cycles: 4)
      when 0xb9 then cp8(:c, cycles: 4)
      when 0xba then cp8(:d, cycles: 4)
      when 0xbb then cp8(:e, cycles: 4)
      when 0xbc then cp8(:h, cycles: 4)
      when 0xbd then cp8(:l, cycles: 4)
      when 0xbe then cp8(:indirect_hl, cycles: 8)
      when 0xbf then cp8(:a, cycles: 4)
      when 0xc0 then ret_if(condition: !flag_z)
      when 0xc1 then pop16(:bc, cycles: 12)
      when 0xc2 then jp(:immediate16, condition: !flag_z)
      when 0xc3 then jp(:immediate16, condition: true)
      when 0xc4 then call16(:immediate16, condition: !flag_z)
      when 0xc5 then push16(:bc, cycles: 16)
      when 0xc6 then add8(:immediate8, cycles: 8)
      when 0xc7 then rst(0x00, cycles: 16)
      when 0xc8 then ret_if(condition: flag_z)
      when 0xc9 then ret(cycles: 16)
      when 0xca then jp(:immediate16, condition: flag_z)
      when 0xcc then call16(:immediate16, condition: flag_z)
      when 0xcd then call16(:immediate16, condition: true)
      when 0xce then adc8(:immediate8, cycles: 8)
      when 0xcf then rst(0x08, cycles: 16)
      when 0xd0 then ret_if(condition: !flag_c)
      when 0xd1 then pop16(:de, cycles: 12)
      when 0xd2 then jp(:immediate16, condition: !flag_c)
      when 0xd4 then call16(:immediate16, condition: !flag_c)
      when 0xd5 then push16(:de, cycles: 16)
      when 0xd6 then sub8(:immediate8, cycles: 8)
      when 0xd7 then rst(0x10, cycles: 16)
      when 0xd8 then ret_if(condition: flag_c)
      when 0xd9 then reti(cycles: 16)
      when 0xda then jp(:immediate16, condition: flag_c)
      when 0xdc then call16(:immediate16, condition: flag_c)
      when 0xde then sbc8(:immediate8, cycles: 8)
      when 0xdf then rst(0x18, cycles: 16)
      when 0xe0 then ld8(:ff00, :a, cycles: 12)
      when 0xe1 then pop16(:hl, cycles: 12)
      when 0xe2 then ld8(:ff00_c, :a, cycles: 8)
      when 0xe5 then push16(:hl, cycles: 16)
      when 0xe6 then and8(:immediate8, cycles: 8)
      when 0xe7 then rst(0x20, cycles: 16)
      when 0xe8 then add_sp_r8(cycles: 16)
      when 0xe9 then jp_hl(cycles: 4)
      when 0xea then ld8(:direct8, :a, cycles: 16)
      when 0xee then xor8(:immediate8, cycles: 8)
      when 0xef then rst(0x28, cycles: 16)
      when 0xf0 then ld8(:a, :ff00, cycles: 12)
      when 0xf1 then pop16(:af, cycles: 12)
      when 0xf2 then ld8(:a, :ff00_c, cycles: 8)
      when 0xf3 then di(cycles: 4)
      when 0xf5 then push16(:af, cycles: 16)
      when 0xf6 then or8(:immediate8, cycles: 8)
      when 0xf7 then rst(0x30, cycles: 16)
      when 0xf8 then ld_hl_sp_r8(cycles: 12)
      when 0xf9 then ld16(:sp, :hl, cycles: 8)
      when 0xfa then ld8(:a, :direct8, cycles: 16)
      when 0xfb then ei(cycles: 4)
      when 0xfe then cp8(:immediate8, cycles: 8)
      when 0xff then rst(0x38, cycles: 16)
      when 0xcb # CB prefix
        opcode = read_byte_and_advance_pc

        case opcode
        when 0x00 then rlc8(:b, cycles: 8)
        when 0x01 then rlc8(:c, cycles: 8)
        when 0x02 then rlc8(:d, cycles: 8)
        when 0x03 then rlc8(:e, cycles: 8)
        when 0x04 then rlc8(:h, cycles: 8)
        when 0x05 then rlc8(:l, cycles: 8)
        when 0x06 then rlc8(:indirect_hl, cycles: 16)
        when 0x07 then rlc8(:a, cycles: 8)
        when 0x08 then rrc8(:b, cycles: 8)
        when 0x09 then rrc8(:c, cycles: 8)
        when 0x0a then rrc8(:d, cycles: 8)
        when 0x0b then rrc8(:e, cycles: 8)
        when 0x0c then rrc8(:h, cycles: 8)
        when 0x0d then rrc8(:l, cycles: 8)
        when 0x0e then rrc8(:indirect_hl, cycles: 16)
        when 0x0f then rrc8(:a, cycles: 8)
        when 0x10 then rl8(:b, cycles: 8)
        when 0x11 then rl8(:c, cycles: 8)
        when 0x12 then rl8(:d, cycles: 8)
        when 0x13 then rl8(:e, cycles: 8)
        when 0x14 then rl8(:h, cycles: 8)
        when 0x15 then rl8(:l, cycles: 8)
        when 0x16 then rl8(:indirect_hl, cycles: 16)
        when 0x17 then rl8(:a, cycles: 8)
        when 0x18 then rr8(:b, cycles: 8)
        when 0x19 then rr8(:c, cycles: 8)
        when 0x1a then rr8(:d, cycles: 8)
        when 0x1b then rr8(:e, cycles: 8)
        when 0x1c then rr8(:h, cycles: 8)
        when 0x1d then rr8(:l, cycles: 8)
        when 0x1e then rr8(:indirect_hl, cycles: 16)
        when 0x1f then rr8(:a, cycles: 8)
        when 0x20 then sla8(:b, cycles: 8)
        when 0x21 then sla8(:c, cycles: 8)
        when 0x22 then sla8(:d, cycles: 8)
        when 0x23 then sla8(:e, cycles: 8)
        when 0x24 then sla8(:h, cycles: 8)
        when 0x25 then sla8(:l, cycles: 8)
        when 0x26 then sla8(:indirect_hl, cycles: 16)
        when 0x27 then sla8(:a, cycles: 8)
        when 0x28 then sra8(:b, cycles: 8)
        when 0x29 then sra8(:c, cycles: 8)
        when 0x2a then sra8(:d, cycles: 8)
        when 0x2b then sra8(:e, cycles: 8)
        when 0x2c then sra8(:h, cycles: 8)
        when 0x2d then sra8(:l, cycles: 8)
        when 0x2e then sra8(:indirect_hl, cycles: 16)
        when 0x2f then sra8(:a, cycles: 8)
        when 0x30 then swap8(:b, cycles: 8)
        when 0x31 then swap8(:c, cycles: 8)
        when 0x32 then swap8(:d, cycles: 8)
        when 0x33 then swap8(:e, cycles: 8)
        when 0x34 then swap8(:h, cycles: 8)
        when 0x35 then swap8(:l, cycles: 8)
        when 0x36 then swap8(:indirect_hl, cycles: 16)
        when 0x37 then swap8(:a, cycles: 8)
        when 0x38 then srl8(:b, cycles: 8)
        when 0x39 then srl8(:c, cycles: 8)
        when 0x3a then srl8(:d, cycles: 8)
        when 0x3b then srl8(:e, cycles: 8)
        when 0x3c then srl8(:h, cycles: 8)
        when 0x3d then srl8(:l, cycles: 8)
        when 0x3e then srl8(:indirect_hl, cycles: 16)
        when 0x3f then srl8(:a, cycles: 8)
        when 0x40 then bit8(0, :b, cycles: 8)
        when 0x41 then bit8(0, :c, cycles: 8)
        when 0x42 then bit8(0, :d, cycles: 8)
        when 0x43 then bit8(0, :e, cycles: 8)
        when 0x44 then bit8(0, :h, cycles: 8)
        when 0x45 then bit8(0, :l, cycles: 8)
        when 0x46 then bit8(0, :indirect_hl, cycles: 12)
        when 0x47 then bit8(0, :a, cycles: 8)
        when 0x48 then bit8(1, :b, cycles: 8)
        when 0x49 then bit8(1, :c, cycles: 8)
        when 0x4a then bit8(1, :d, cycles: 8)
        when 0x4b then bit8(1, :e, cycles: 8)
        when 0x4c then bit8(1, :h, cycles: 8)
        when 0x4d then bit8(1, :l, cycles: 8)
        when 0x4e then bit8(1, :indirect_hl, cycles: 12)
        when 0x4f then bit8(1, :a, cycles: 8)
        when 0x50 then bit8(2, :b, cycles: 8)
        when 0x51 then bit8(2, :c, cycles: 8)
        when 0x52 then bit8(2, :d, cycles: 8)
        when 0x53 then bit8(2, :e, cycles: 8)
        when 0x54 then bit8(2, :h, cycles: 8)
        when 0x55 then bit8(2, :l, cycles: 8)
        when 0x56 then bit8(2, :indirect_hl, cycles: 12)
        when 0x57 then bit8(2, :a, cycles: 8)
        when 0x58 then bit8(3, :b, cycles: 8)
        when 0x59 then bit8(3, :c, cycles: 8)
        when 0x5a then bit8(3, :d, cycles: 8)
        when 0x5b then bit8(3, :e, cycles: 8)
        when 0x5c then bit8(3, :h, cycles: 8)
        when 0x5d then bit8(3, :l, cycles: 8)
        when 0x5e then bit8(3, :indirect_hl, cycles: 12)
        when 0x5f then bit8(3, :a, cycles: 8)
        when 0x60 then bit8(4, :b, cycles: 8)
        when 0x61 then bit8(4, :c, cycles: 8)
        when 0x62 then bit8(4, :d, cycles: 8)
        when 0x63 then bit8(4, :e, cycles: 8)
        when 0x64 then bit8(4, :h, cycles: 8)
        when 0x65 then bit8(4, :l, cycles: 8)
        when 0x66 then bit8(4, :indirect_hl, cycles: 12)
        when 0x67 then bit8(4, :a, cycles: 8)
        when 0x68 then bit8(5, :b, cycles: 8)
        when 0x69 then bit8(5, :c, cycles: 8)
        when 0x6a then bit8(5, :d, cycles: 8)
        when 0x6b then bit8(5, :e, cycles: 8)
        when 0x6c then bit8(5, :h, cycles: 8)
        when 0x6d then bit8(5, :l, cycles: 8)
        when 0x6e then bit8(5, :indirect_hl, cycles: 12)
        when 0x6f then bit8(5, :a, cycles: 8)
        when 0x70 then bit8(6, :b, cycles: 8)
        when 0x71 then bit8(6, :c, cycles: 8)
        when 0x72 then bit8(6, :d, cycles: 8)
        when 0x73 then bit8(6, :e, cycles: 8)
        when 0x74 then bit8(6, :h, cycles: 8)
        when 0x75 then bit8(6, :l, cycles: 8)
        when 0x76 then bit8(6, :indirect_hl, cycles: 12)
        when 0x77 then bit8(6, :a, cycles: 8)
        when 0x78 then bit8(7, :b, cycles: 8)
        when 0x79 then bit8(7, :c, cycles: 8)
        when 0x7a then bit8(7, :d, cycles: 8)
        when 0x7b then bit8(7, :e, cycles: 8)
        when 0x7c then bit8(7, :h, cycles: 8)
        when 0x7d then bit8(7, :l, cycles: 8)
        when 0x7e then bit8(7, :indirect_hl, cycles: 12)
        when 0x7f then bit8(7, :a, cycles: 8)
        when 0x80 then res8(0, :b, cycles: 8)
        when 0x81 then res8(0, :c, cycles: 8)
        when 0x82 then res8(0, :d, cycles: 8)
        when 0x83 then res8(0, :e, cycles: 8)
        when 0x84 then res8(0, :h, cycles: 8)
        when 0x85 then res8(0, :l, cycles: 8)
        when 0x86 then res8(0, :indirect_hl, cycles: 16)
        when 0x87 then res8(0, :a, cycles: 8)
        when 0x88 then res8(1, :b, cycles: 8)
        when 0x89 then res8(1, :c, cycles: 8)
        when 0x8a then res8(1, :d, cycles: 8)
        when 0x8b then res8(1, :e, cycles: 8)
        when 0x8c then res8(1, :h, cycles: 8)
        when 0x8d then res8(1, :l, cycles: 8)
        when 0x8e then res8(1, :indirect_hl, cycles: 16)
        when 0x8f then res8(1, :a, cycles: 8)
        when 0x90 then res8(2, :b, cycles: 8)
        when 0x91 then res8(2, :c, cycles: 8)
        when 0x92 then res8(2, :d, cycles: 8)
        when 0x93 then res8(2, :e, cycles: 8)
        when 0x94 then res8(2, :h, cycles: 8)
        when 0x95 then res8(2, :l, cycles: 8)
        when 0x96 then res8(2, :indirect_hl, cycles: 16)
        when 0x97 then res8(2, :a, cycles: 8)
        when 0x98 then res8(3, :b, cycles: 8)
        when 0x99 then res8(3, :c, cycles: 8)
        when 0x9a then res8(3, :d, cycles: 8)
        when 0x9b then res8(3, :e, cycles: 8)
        when 0x9c then res8(3, :h, cycles: 8)
        when 0x9d then res8(3, :l, cycles: 8)
        when 0x9e then res8(3, :indirect_hl, cycles: 16)
        when 0x9f then res8(3, :a, cycles: 8)
        when 0xa0 then res8(4, :b, cycles: 8)
        when 0xa1 then res8(4, :c, cycles: 8)
        when 0xa2 then res8(4, :d, cycles: 8)
        when 0xa3 then res8(4, :e, cycles: 8)
        when 0xa4 then res8(4, :h, cycles: 8)
        when 0xa5 then res8(4, :l, cycles: 8)
        when 0xa6 then res8(4, :indirect_hl, cycles: 16)
        when 0xa7 then res8(4, :a, cycles: 8)
        when 0xa8 then res8(5, :b, cycles: 8)
        when 0xa9 then res8(5, :c, cycles: 8)
        when 0xaa then res8(5, :d, cycles: 8)
        when 0xab then res8(5, :e, cycles: 8)
        when 0xac then res8(5, :h, cycles: 8)
        when 0xad then res8(5, :l, cycles: 8)
        when 0xae then res8(5, :indirect_hl, cycles: 16)
        when 0xaf then res8(5, :a, cycles: 8)
        when 0xb0 then res8(6, :b, cycles: 8)
        when 0xb1 then res8(6, :c, cycles: 8)
        when 0xb2 then res8(6, :d, cycles: 8)
        when 0xb3 then res8(6, :e, cycles: 8)
        when 0xb4 then res8(6, :h, cycles: 8)
        when 0xb5 then res8(6, :l, cycles: 8)
        when 0xb6 then res8(6, :indirect_hl, cycles: 16)
        when 0xb7 then res8(6, :a, cycles: 8)
        when 0xb8 then res8(7, :b, cycles: 8)
        when 0xb9 then res8(7, :c, cycles: 8)
        when 0xba then res8(7, :d, cycles: 8)
        when 0xbb then res8(7, :e, cycles: 8)
        when 0xbc then res8(7, :h, cycles: 8)
        when 0xbd then res8(7, :l, cycles: 8)
        when 0xbe then res8(7, :indirect_hl, cycles: 16)
        when 0xbf then res8(7, :a, cycles: 8)
        when 0xc0 then set8(0, :b, cycles: 8)
        when 0xc1 then set8(0, :c, cycles: 8)
        when 0xc2 then set8(0, :d, cycles: 8)
        when 0xc3 then set8(0, :e, cycles: 8)
        when 0xc4 then set8(0, :h, cycles: 8)
        when 0xc5 then set8(0, :l, cycles: 8)
        when 0xc6 then set8(0, :indirect_hl, cycles: 16)
        when 0xc7 then set8(0, :a, cycles: 8)
        when 0xc8 then set8(1, :b, cycles: 8)
        when 0xc9 then set8(1, :c, cycles: 8)
        when 0xca then set8(1, :d, cycles: 8)
        when 0xcb then set8(1, :e, cycles: 8)
        when 0xcc then set8(1, :h, cycles: 8)
        when 0xcd then set8(1, :l, cycles: 8)
        when 0xce then set8(1, :indirect_hl, cycles: 16)
        when 0xcf then set8(1, :a, cycles: 8)
        when 0xd0 then set8(2, :b, cycles: 8)
        when 0xd1 then set8(2, :c, cycles: 8)
        when 0xd2 then set8(2, :d, cycles: 8)
        when 0xd3 then set8(2, :e, cycles: 8)
        when 0xd4 then set8(2, :h, cycles: 8)
        when 0xd5 then set8(2, :l, cycles: 8)
        when 0xd6 then set8(2, :indirect_hl, cycles: 16)
        when 0xd7 then set8(2, :a, cycles: 8)
        when 0xd8 then set8(3, :b, cycles: 8)
        when 0xd9 then set8(3, :c, cycles: 8)
        when 0xda then set8(3, :d, cycles: 8)
        when 0xdb then set8(3, :e, cycles: 8)
        when 0xdc then set8(3, :h, cycles: 8)
        when 0xdd then set8(3, :l, cycles: 8)
        when 0xde then set8(3, :indirect_hl, cycles: 16)
        when 0xdf then set8(3, :a, cycles: 8)
        when 0xe0 then set8(4, :b, cycles: 8)
        when 0xe1 then set8(4, :c, cycles: 8)
        when 0xe2 then set8(4, :d, cycles: 8)
        when 0xe3 then set8(4, :e, cycles: 8)
        when 0xe4 then set8(4, :h, cycles: 8)
        when 0xe5 then set8(4, :l, cycles: 8)
        when 0xe6 then set8(4, :indirect_hl, cycles: 16)
        when 0xe7 then set8(4, :a, cycles: 8)
        when 0xe8 then set8(5, :b, cycles: 8)
        when 0xe9 then set8(5, :c, cycles: 8)
        when 0xea then set8(5, :d, cycles: 8)
        when 0xeb then set8(5, :e, cycles: 8)
        when 0xec then set8(5, :h, cycles: 8)
        when 0xed then set8(5, :l, cycles: 8)
        when 0xee then set8(5, :indirect_hl, cycles: 16)
        when 0xef then set8(5, :a, cycles: 8)
        when 0xf0 then set8(6, :b, cycles: 8)
        when 0xf1 then set8(6, :c, cycles: 8)
        when 0xf2 then set8(6, :d, cycles: 8)
        when 0xf3 then set8(6, :e, cycles: 8)
        when 0xf4 then set8(6, :h, cycles: 8)
        when 0xf5 then set8(6, :l, cycles: 8)
        when 0xf6 then set8(6, :indirect_hl, cycles: 16)
        when 0xf7 then set8(6, :a, cycles: 8)
        when 0xf8 then set8(7, :b, cycles: 8)
        when 0xf9 then set8(7, :c, cycles: 8)
        when 0xfa then set8(7, :d, cycles: 8)
        when 0xfb then set8(7, :e, cycles: 8)
        when 0xfc then set8(7, :h, cycles: 8)
        when 0xfd then set8(7, :l, cycles: 8)
        when 0xfe then set8(7, :indirect_hl, cycles: 16)
        when 0xff then set8(7, :a, cycles: 8)
        else
          raise "unknown opcode: 0xcb 0x#{'%02x' % opcode}"
        end
      else
        raise "unknown opcode: 0x#{'%02x' % opcode}"
      end
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
      puts "PC: 0x#{'%04x' % @pc}, Opcode: 0x#{'%02x' % opcode}, AF: 0x#{'%04x' % @registers.af}, BC: 0x#{'%04x' % @registers.bc}, HL: 0x#{'%04x' % @registers.hl}, SP: 0x#{'%04x' % @sp}"
    end

    def flag_z
      @registers.f[7] == 1
    end

    def flag_n
      @registers.f[6] == 1
    end

    def flag_h
      @registers.f[5] == 1
    end

    def flag_c
      @registers.f[4] == 1
    end

    def update_flags(z: flag_z, n: flag_n, h: flag_h, c: flag_c)
      f_value = 0x00
      f_value |= 0x80 if z
      f_value |= 0x40 if n
      f_value |= 0x20 if h
      f_value |= 0x10 if c

      @registers.f = f_value
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

    def to_signed_byte(byte)
      byte &= 0xff
      byte > 127 ? byte - 256 : byte
    end

    def rlca(cycles:)
      a_value = @registers.a
      a_value = ((a_value << 1) | (a_value >> 7)) & 0xff
      @registers.a = a_value
      update_flags(
        z: false,
        n: false,
        h: false,
        c: a_value[0] == 1
      )

      cycles
    end

    def rrca(cycles:)
      a_value = @registers.a
      a_value = ((a_value >> 1) | (a_value << 7)) & 0xff
      @registers.a = a_value
      update_flags(
        z: false,
        n: false,
        h: false,
        c: a_value[7] == 1
      )

      cycles
    end

    def rra(cycles:)
      a_value = @registers.a
      cflag = a_value[0] == 1
      a_value = ((a_value >> 1) | (bool_to_integer(flag_c) << 7)) & 0xff
      @registers.a = a_value
      update_flags(
        z: false,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def rla(cycles:)
      a_value = @registers.a
      cflag = a_value[7] == 1
      a_value = ((a_value << 1) | bool_to_integer(flag_c)) & 0xff
      @registers.a = a_value
      update_flags(
        z: false,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def daa(cycles:)
      a_value = @registers.a
      if flag_n
        a_value -= 0x06 if flag_h
        a_value -= 0x60 if flag_c
      else
        if flag_c || a_value > 0x99
          a_value += 0x60
          update_flags(c: true)
        end
        a_value += 0x06 if flag_h || (a_value & 0x0f) > 0x09
      end

      @registers.a = a_value
      update_flags(
        z: @registers.a == 0,
        h: false
      )

      cycles
    end

    def cpl(cycles:)
      @registers.a = ~@registers.a
      update_flags(
        n: true,
        h: true
      )

      cycles
    end

    def scf(cycles:)
      update_flags(
        n: false,
        h: false,
        c: true
      )

      cycles
    end

    def ccf(cycles:)
      update_flags(
        n: false,
        h: false,
        c: !flag_c
      )

      cycles
    end

    def inc8(x, cycles:)
      value = (get_value(x) + 1) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: (value & 0x0f) == 0
      )

      cycles
    end

    def inc16(x, cycles:)
      set_value(x, get_value(x) + 1)

      cycles
    end

    def dec8(x, cycles:)
      value = (get_value(x) - 1) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: true,
        h: (value & 0x0f) == 0x0f
      )

      cycles
    end

    def dec16(x, cycles:)
      set_value(x, get_value(x) - 1)

      cycles
    end

    def add8(x, cycles:)
      a_value = @registers.a
      x_value = get_value(x)

      hflag = (a_value & 0x0f) + (x_value & 0x0f) > 0x0f
      cflag = a_value + x_value > 0xff

      a_value += x_value
      @registers.a = a_value
      update_flags(
        z: @registers.a == 0,
        n: false,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def add16(x, y, cycles:)
      x_value = get_value(x)
      y_value = get_value(y)

      hflag = (x_value & 0x0fff) + (y_value & 0x0fff) > 0x0fff
      cflag = x_value + y_value > 0xffff

      set_value(x, x_value + y_value)
      update_flags(
        n: false,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def add_sp_r8(cycles:)
      byte = to_signed_byte(read_byte_and_advance_pc)

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

      cycles
    end

    def sub8(x, cycles:)
      a_value = @registers.a
      x_value = get_value(x)

      hflag = (x_value & 0x0f) > (a_value & 0x0f)
      cflag = x_value > a_value
      a_value -= x_value
      @registers.a = a_value
      update_flags(
        z: a_value == 0,
        n: true,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def adc8(x, cycles:)
      a_value = @registers.a
      x_value = get_value(x)
      c_value = bool_to_integer(flag_c)

      hflag = (a_value & 0x0f) + (x_value & 0x0f) + c_value > 0x0f
      cflag = a_value + x_value + c_value > 0xff
      a_value += x_value + c_value
      @registers.a = a_value
      update_flags(
        z: @registers.a == 0,
        n: false,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def sbc8(x, cycles:)
      a_value = @registers.a
      x_value = get_value(x)
      c_value = bool_to_integer(flag_c)

      hflag = (x_value & 0x0f) + c_value > (a_value & 0x0f)
      cflag = x_value + c_value > a_value
      a_value -= x_value + c_value
      @registers.a = a_value
      update_flags(
        z: @registers.a == 0,
        n: true,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def and8(x, cycles:)
      a_value = @registers.a & get_value(x)
      @registers.a = a_value
      update_flags(
        z: a_value == 0,
        n: false,
        h: true,
        c: false
      )

      cycles
    end

    def or8(x, cycles:)
      a_value = @registers.a | get_value(x)
      @registers.a = a_value
      update_flags(
        z: a_value == 0,
        n: false,
        h: false,
        c: false
      )

      cycles
    end

    def xor8(x, cycles:)
      a_value = @registers.a ^ get_value(x)
      @registers.a = a_value
      update_flags(
        z: a_value == 0,
        n: false,
        h: false,
        c: false
      )

      cycles
    end

    def push16(register16, cycles:)
      @sp -= 2
      write_word(@sp, get_value(register16))

      cycles
    end

    def pop16(register16, cycles:)
      set_value(register16, read_word(@sp))
      @sp += 2

      cycles
    end

    def halt(cycles:)
      @halted = true

      cycles
    end

    def ld8(x, y, cycles:)
      value = get_value(y)
      set_value(x, value)

      cycles
    end

    def ld16(x, y, cycles:)
      value = get_value(y)
      set_value(x, value)

      cycles
    end

    def ld_hl_sp_r8(cycles:)
      byte = to_signed_byte(read_byte_and_advance_pc)

      hflag = (@sp & 0x0f) + (byte & 0x0f) > 0x0f
      cflag = (@sp & 0xff) + (byte & 0xff) > 0xff
      @registers.hl = @sp + byte
      update_flags(
        z: false,
        n: false,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def ei(cycles:)
      @ime_delay = true

      cycles
    end

    def di(cycles:)
      @ime_delay = false
      @ime = false

      cycles
    end

    def cp8(x, cycles:)
      a_value = @registers.a
      x_value = get_value(x)

      hflag = (x_value & 0x0f) > (a_value & 0x0f)
      cflag = x_value > a_value
      update_flags(
        z: a_value == x_value,
        n: true,
        h: hflag,
        c: cflag
      )

      cycles
    end

    def rst(addr, cycles:)
      @sp -= 2
      write_word(@sp, @pc)
      @pc = addr

      cycles
    end

    def jr(condition:)
      value = to_signed_byte(read_byte_and_advance_pc)
      @pc += value if condition

      condition ? 12 : 8
    end

    def jp(x, condition:)
      addr = get_value(x)
      @pc = addr if condition

      condition ? 16 : 12
    end

    def jp_hl(cycles:)
      @pc = @registers.hl

      cycles
    end

    def call16(x, condition:)
      addr = get_value(x)
      if condition
        @sp -= 2
        write_word(@sp, @pc)
        @pc = addr
      end

      condition ? 24 : 12
    end

    def ret(cycles:)
      @pc = read_word(@sp)
      @sp += 2

      cycles
    end

    def ret_if(condition:)
      ret(cycles: 16) if condition

      condition ? 20 : 8
    end

    def reti(cycles:)
      @ime = true
      ret(cycles:)
    end

    def rlc8(x, cycles:)
      value = get_value(x)
      value = (value << 1) | (value >> 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: value[0] == 1
      )

      cycles
    end

    def rrc8(x, cycles:)
      value = get_value(x)
      value = (value >> 1) | (value << 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: value[7] == 1
      )

      cycles
    end

    def rl8(x, cycles:)
      value = get_value(x)
      cflag = value[7] == 1
      value = ((value << 1) | bool_to_integer(flag_c)) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def rr8(x, cycles:)
      value = get_value(x)
      cflag = value[0] == 1
      value = (value >> 1) | (bool_to_integer(flag_c) << 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def sla8(x, cycles:)
      value = get_value(x)
      cflag = value[7] == 1
      value <<= 1
      value &= 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def sra8(x, cycles:)
      value = get_value(x)
      cflag = value[0] == 1
      value = (value >> 1) | (value[7] << 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def swap8(x, cycles:)
      value = get_value(x)
      value = ((value & 0x0f) << 4) | ((value & 0xf0) >> 4)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: false
      )

      cycles
    end

    def srl8(x, cycles:)
      value = get_value(x)
      cflag = value[0] == 1
      value >>= 1
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      cycles
    end

    def bit8(n, x, cycles:)
      value = get_value(x)
      update_flags(
        z: value[n] == 0,
        n: false,
        h: true
      )

      cycles
    end

    def res8(n, x, cycles:)
      value = get_value(x)
      value &= ((~(1 << n)) & 0xff)
      set_value(x, value)

      cycles
    end

    def set8(n, x, cycles:)
      value = get_value(x)
      value |= (1 << n)
      set_value(x, value)

      cycles
    end

    def get_value(operand)
      case operand
      when :a then @registers.a
      when :b then @registers.b
      when :c then @registers.c
      when :d then @registers.d
      when :e then @registers.e
      when :h then @registers.h
      when :l then @registers.l
      when :f then @registers.f
      when :af then @registers.af
      when :bc then @registers.bc
      when :de then @registers.de
      when :hl then @registers.hl
      when :sp then @sp
      when :immediate8 then read_byte_and_advance_pc
      when :immediate16 then read_word_and_advance_pc
      when :direct8 then read_byte(read_word_and_advance_pc)
      when :direct16 then read_word(read_word_and_advance_pc)
      when :ff00 then read_byte(0xff00 + read_byte_and_advance_pc)
      when :ff00_c then read_byte(0xff00 + @registers.c)
      when :hl_inc
        value = read_byte(@registers.hl)
        @registers.hl += 1
        value
      when :hl_dec
        value = read_byte(@registers.hl)
        @registers.hl -= 1
        value
      when :indirect_hl then read_byte(@registers.hl)
      when :indirect_bc then read_byte(@registers.bc)
      when :indirect_de then read_byte(@registers.de)
      else raise "unknown operand: #{operand}"
      end
    end

    def set_value(operand, value)
      case operand
      when :a then @registers.a = value
      when :b then @registers.b = value
      when :c then @registers.c = value
      when :d then @registers.d = value
      when :e then @registers.e = value
      when :h then @registers.h = value
      when :l then @registers.l = value
      when :f then @registers.f = value
      when :af then @registers.af = value
      when :bc then @registers.bc = value
      when :de then @registers.de = value
      when :hl then @registers.hl = value
      when :sp then @sp = value & 0xffff
      when :direct8 then write_byte(read_word_and_advance_pc, value)
      when :direct16 then write_word(read_word_and_advance_pc, value)
      when :ff00 then write_byte(0xff00 + read_byte_and_advance_pc, value)
      when :ff00_c then write_byte(0xff00 + @registers.c, value)
      when :hl_inc
        write_byte(@registers.hl, value)
        @registers.hl += 1
      when :hl_dec
        write_byte(@registers.hl, value)
        @registers.hl -= 1
      when :indirect_hl then write_byte(@registers.hl, value)
      when :indirect_bc then write_byte(@registers.bc, value)
      when :indirect_de then write_byte(@registers.de, value)
      when :immediate8, :immediate16 then raise 'immediate type is read only'
      else raise "unknown operand: #{operand}"
      end
    end
  end
end
