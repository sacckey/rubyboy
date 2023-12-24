# frozen_string_literal: true

require_relative 'registers'
require_relative 'operand'

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
      when 0x01 then ld16(Operand.new(type: :register16, value: :bc), Operand.new(type: :immediate16))
      when 0x02 then ld8(Operand.new(type: :indirect, value: :bc), Operand.new(type: :register8, value: :a))
      when 0x03 then inc16(Operand.new(type: :register16, value: :bc))
      when 0x04 then inc8(Operand.new(type: :register8, value: :b))
      when 0x05 then dec8(Operand.new(type: :register8, value: :b))
      when 0x06 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :immediate8))
      when 0x07 then rlca
      when 0x08 then ld16(Operand.new(type: :direct16), Operand.new(type: :sp))
      when 0x09 then add16(Operand.new(type: :register16, value: :hl), Operand.new(type: :register16, value: :bc))
      when 0x0a then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :indirect, value: :bc))
      when 0x0b then dec16(Operand.new(type: :register16, value: :bc))
      when 0x0c then inc8(Operand.new(type: :register8, value: :c))
      when 0x0d then dec8(Operand.new(type: :register8, value: :c))
      when 0x0e then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :immediate8))
      when 0x0f then rrca
      when 0x10 then 4 # STOP
      when 0x11 then ld16(Operand.new(type: :register16, value: :de), Operand.new(type: :immediate16))
      when 0x12 then ld8(Operand.new(type: :indirect, value: :de), Operand.new(type: :register8, value: :a))
      when 0x13 then inc16(Operand.new(type: :register16, value: :de))
      when 0x14 then inc8(Operand.new(type: :register8, value: :d))
      when 0x15 then dec8(Operand.new(type: :register8, value: :d))
      when 0x16 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :immediate8))
      when 0x17 then rla
      when 0x18 then jr
      when 0x19 then add16(Operand.new(type: :register16, value: :hl), Operand.new(type: :register16, value: :de))
      when 0x1a then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :indirect, value: :de))
      when 0x1b then dec16(Operand.new(type: :register16, value: :de))
      when 0x1c then inc8(Operand.new(type: :register8, value: :e))
      when 0x1d then dec8(Operand.new(type: :register8, value: :e))
      when 0x1e then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :immediate8))
      when 0x1f then rra
      when 0x20 then jr(condition: !flags[:z])
      when 0x21 then ld16(Operand.new(type: :register16, value: :hl), Operand.new(type: :immediate16))
      when 0x22 then ld8(Operand.new(type: :hl_inc), Operand.new(type: :register8, value: :a))
      when 0x23 then inc16(Operand.new(type: :register16, value: :hl))
      when 0x24 then inc8(Operand.new(type: :register8, value: :h))
      when 0x25 then dec8(Operand.new(type: :register8, value: :h))
      when 0x26 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :immediate8))
      when 0x27 then daa
      when 0x28 then jr(condition: flags[:z])
      when 0x29 then add16(Operand.new(type: :register16, value: :hl), Operand.new(type: :register16, value: :hl))
      when 0x2a then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :hl_inc))
      when 0x2b then dec16(Operand.new(type: :register16, value: :hl))
      when 0x2c then inc8(Operand.new(type: :register8, value: :l))
      when 0x2d then dec8(Operand.new(type: :register8, value: :l))
      when 0x2e then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :immediate8))
      when 0x2f then cpl
      when 0x30 then jr(condition: !flags[:c])
      when 0x31 then ld16(Operand.new(type: :sp), Operand.new(type: :immediate16))
      when 0x32 then ld8(Operand.new(type: :hl_dec), Operand.new(type: :register8, value: :a))
      when 0x33 then inc16(Operand.new(type: :sp))
      when 0x34 then inc8(Operand.new(type: :indirect, value: :hl))
      when 0x35 then dec8(Operand.new(type: :indirect, value: :hl))
      when 0x36 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :immediate8))
      when 0x37 then scf
      when 0x38 then jr(condition: flags[:c])
      when 0x39 then add16(Operand.new(type: :register16, value: :hl), Operand.new(type: :sp))
      when 0x3a then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :hl_dec))
      when 0x3b then dec16(Operand.new(type: :sp))
      when 0x3c then inc8(Operand.new(type: :register8, value: :a))
      when 0x3d then dec8(Operand.new(type: :register8, value: :a))
      when 0x3e then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :immediate8))
      when 0x3f then ccf
      when 0x40 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :b))
      when 0x41 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :c))
      when 0x42 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :d))
      when 0x43 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :e))
      when 0x44 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :h))
      when 0x45 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :l))
      when 0x46 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :indirect, value: :hl))
      when 0x47 then ld8(Operand.new(type: :register8, value: :b), Operand.new(type: :register8, value: :a))
      when 0x48 then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :b))
      when 0x49 then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :c))
      when 0x4a then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :d))
      when 0x4b then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :e))
      when 0x4c then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :h))
      when 0x4d then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :l))
      when 0x4e then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :indirect, value: :hl))
      when 0x4f then ld8(Operand.new(type: :register8, value: :c), Operand.new(type: :register8, value: :a))
      when 0x50 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :b))
      when 0x51 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :c))
      when 0x52 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :d))
      when 0x53 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :e))
      when 0x54 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :h))
      when 0x55 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :l))
      when 0x56 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :indirect, value: :hl))
      when 0x57 then ld8(Operand.new(type: :register8, value: :d), Operand.new(type: :register8, value: :a))
      when 0x58 then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :b))
      when 0x59 then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :c))
      when 0x5a then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :d))
      when 0x5b then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :e))
      when 0x5c then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :h))
      when 0x5d then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :l))
      when 0x5e then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :indirect, value: :hl))
      when 0x5f then ld8(Operand.new(type: :register8, value: :e), Operand.new(type: :register8, value: :a))
      when 0x60 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :b))
      when 0x61 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :c))
      when 0x62 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :d))
      when 0x63 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :e))
      when 0x64 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :h))
      when 0x65 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :l))
      when 0x66 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :indirect, value: :hl))
      when 0x67 then ld8(Operand.new(type: :register8, value: :h), Operand.new(type: :register8, value: :a))
      when 0x68 then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :b))
      when 0x69 then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :c))
      when 0x6a then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :d))
      when 0x6b then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :e))
      when 0x6c then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :h))
      when 0x6d then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :l))
      when 0x6e then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :indirect, value: :hl))
      when 0x6f then ld8(Operand.new(type: :register8, value: :l), Operand.new(type: :register8, value: :a))
      when 0x70 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :b))
      when 0x71 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :c))
      when 0x72 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :d))
      when 0x73 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :e))
      when 0x74 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :h))
      when 0x75 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :l))
      when 0x76 then halt
      when 0x77 then ld8(Operand.new(type: :indirect, value: :hl), Operand.new(type: :register8, value: :a))
      when 0x78 then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :b))
      when 0x79 then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :c))
      when 0x7a then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :d))
      when 0x7b then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :e))
      when 0x7c then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :h))
      when 0x7d then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :l))
      when 0x7e then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :indirect, value: :hl))
      when 0x7f then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :register8, value: :a))
      when 0x80 then add8(Operand.new(type: :register8, value: :b))
      when 0x81 then add8(Operand.new(type: :register8, value: :c))
      when 0x82 then add8(Operand.new(type: :register8, value: :d))
      when 0x83 then add8(Operand.new(type: :register8, value: :e))
      when 0x84 then add8(Operand.new(type: :register8, value: :h))
      when 0x85 then add8(Operand.new(type: :register8, value: :l))
      when 0x86 then add8(Operand.new(type: :indirect, value: :hl))
      when 0x87 then add8(Operand.new(type: :register8, value: :a))
      when 0x88 then adc8(Operand.new(type: :register8, value: :b))
      when 0x89 then adc8(Operand.new(type: :register8, value: :c))
      when 0x8a then adc8(Operand.new(type: :register8, value: :d))
      when 0x8b then adc8(Operand.new(type: :register8, value: :e))
      when 0x8c then adc8(Operand.new(type: :register8, value: :h))
      when 0x8d then adc8(Operand.new(type: :register8, value: :l))
      when 0x8e then adc8(Operand.new(type: :indirect, value: :hl))
      when 0x8f then adc8(Operand.new(type: :register8, value: :a))
      when 0x90 then sub8(Operand.new(type: :register8, value: :b))
      when 0x91 then sub8(Operand.new(type: :register8, value: :c))
      when 0x92 then sub8(Operand.new(type: :register8, value: :d))
      when 0x93 then sub8(Operand.new(type: :register8, value: :e))
      when 0x94 then sub8(Operand.new(type: :register8, value: :h))
      when 0x95 then sub8(Operand.new(type: :register8, value: :l))
      when 0x96 then sub8(Operand.new(type: :indirect, value: :hl))
      when 0x97 then sub8(Operand.new(type: :register8, value: :a))
      when 0x98 then sbc8(Operand.new(type: :register8, value: :b))
      when 0x99 then sbc8(Operand.new(type: :register8, value: :c))
      when 0x9a then sbc8(Operand.new(type: :register8, value: :d))
      when 0x9b then sbc8(Operand.new(type: :register8, value: :e))
      when 0x9c then sbc8(Operand.new(type: :register8, value: :h))
      when 0x9d then sbc8(Operand.new(type: :register8, value: :l))
      when 0x9e then sbc8(Operand.new(type: :indirect, value: :hl))
      when 0x9f then sbc8(Operand.new(type: :register8, value: :a))
      when 0xa0 then and8(Operand.new(type: :register8, value: :b))
      when 0xa1 then and8(Operand.new(type: :register8, value: :c))
      when 0xa2 then and8(Operand.new(type: :register8, value: :d))
      when 0xa3 then and8(Operand.new(type: :register8, value: :e))
      when 0xa4 then and8(Operand.new(type: :register8, value: :h))
      when 0xa5 then and8(Operand.new(type: :register8, value: :l))
      when 0xa6 then and8(Operand.new(type: :indirect, value: :hl))
      when 0xa7 then and8(Operand.new(type: :register8, value: :a))
      when 0xa8 then xor8(Operand.new(type: :register8, value: :b))
      when 0xa9 then xor8(Operand.new(type: :register8, value: :c))
      when 0xaa then xor8(Operand.new(type: :register8, value: :d))
      when 0xab then xor8(Operand.new(type: :register8, value: :e))
      when 0xac then xor8(Operand.new(type: :register8, value: :h))
      when 0xad then xor8(Operand.new(type: :register8, value: :l))
      when 0xae then xor8(Operand.new(type: :indirect, value: :hl))
      when 0xaf then xor8(Operand.new(type: :register8, value: :a))
      when 0xb0 then or8(Operand.new(type: :register8, value: :b))
      when 0xb1 then or8(Operand.new(type: :register8, value: :c))
      when 0xb2 then or8(Operand.new(type: :register8, value: :d))
      when 0xb3 then or8(Operand.new(type: :register8, value: :e))
      when 0xb4 then or8(Operand.new(type: :register8, value: :h))
      when 0xb5 then or8(Operand.new(type: :register8, value: :l))
      when 0xb6 then or8(Operand.new(type: :indirect, value: :hl))
      when 0xb7 then or8(Operand.new(type: :register8, value: :a))
      when 0xb8 then cp8(Operand.new(type: :register8, value: :b))
      when 0xb9 then cp8(Operand.new(type: :register8, value: :c))
      when 0xba then cp8(Operand.new(type: :register8, value: :d))
      when 0xbb then cp8(Operand.new(type: :register8, value: :e))
      when 0xbc then cp8(Operand.new(type: :register8, value: :h))
      when 0xbd then cp8(Operand.new(type: :register8, value: :l))
      when 0xbe then cp8(Operand.new(type: :indirect, value: :hl))
      when 0xbf then cp8(Operand.new(type: :register8, value: :a))
      when 0xc0 then ret_if(!flags[:z])
      when 0xc1 then pop16(:bc)
      when 0xc2 then jp(Operand.new(type: :immediate16), condition: !flags[:z])
      when 0xc3 then jp(Operand.new(type: :immediate16))
      when 0xc4 then call16(Operand.new(type: :immediate16), condition: !flags[:z])
      when 0xc5 then push16(:bc)
      when 0xc6 then add8(Operand.new(type: :immediate8))
      when 0xc7 then rst(0x00)
      when 0xc8 then ret_if(flags[:z])
      when 0xc9 then ret
      when 0xca then jp(Operand.new(type: :immediate16), condition: flags[:z])
      when 0xcc then call16(Operand.new(type: :immediate16), condition: flags[:z])
      when 0xcd then call16(Operand.new(type: :immediate16))
      when 0xce then adc8(Operand.new(type: :immediate8))
      when 0xcf then rst(0x08)
      when 0xd0 then ret_if(!flags[:c])
      when 0xd1 then pop16(:de)
      when 0xd2 then jp(Operand.new(type: :immediate16), condition: !flags[:c])
      when 0xd4 then call16(Operand.new(type: :immediate16), condition: !flags[:c])
      when 0xd5 then push16(:de)
      when 0xd6 then sub8(Operand.new(type: :immediate8))
      when 0xd7 then rst(0x10)
      when 0xd8 then ret_if(flags[:c])
      when 0xd9 then reti
      when 0xda then jp(Operand.new(type: :immediate16), condition: flags[:c])
      when 0xdc then call16(Operand.new(type: :immediate16), condition: flags[:c])
      when 0xde then sbc8(Operand.new(type: :immediate8))
      when 0xdf then rst(0x18)
      when 0xe0 then ld8(Operand.new(type: :ff00), Operand.new(type: :register8, value: :a))
      when 0xe1 then pop16(:hl)
      when 0xe2 then ld8(Operand.new(type: :ff00_c), Operand.new(type: :register8, value: :a))
      when 0xe5 then push16(:hl)
      when 0xe6 then and8(Operand.new(type: :immediate8))
      when 0xe7 then rst(0x20)
      when 0xe8 then add_sp_r8
      when 0xe9 then jp(Operand.new(type: :register16, value: :hl))
      when 0xea then ld8(Operand.new(type: :direct8), Operand.new(type: :register8, value: :a))
      when 0xee then xor8(Operand.new(type: :immediate8))
      when 0xef then rst(0x28)
      when 0xf0 then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :ff00))
      when 0xf1 then pop16(:af)
      when 0xf2 then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :ff00_c))
      when 0xf3 then di
      when 0xf5 then push16(:af)
      when 0xf6 then or8(Operand.new(type: :immediate8))
      when 0xf7 then rst(0x30)
      when 0xf8 then ld_hl_sp_r8
      when 0xf9 then ld16(Operand.new(type: :sp), Operand.new(type: :register16, value: :hl))
      when 0xfa then ld8(Operand.new(type: :register8, value: :a), Operand.new(type: :direct8))
      when 0xfb then ei
      when 0xfe then cp8(Operand.new(type: :immediate8))
      when 0xff then rst(0x38)
      when 0xcb # CB prefix
        opcode = read_byte_and_advance_pc

        case opcode
        when 0x00 then rlc8(Operand.new(type: :register8, value: :b))
        when 0x01 then rlc8(Operand.new(type: :register8, value: :c))
        when 0x02 then rlc8(Operand.new(type: :register8, value: :d))
        when 0x03 then rlc8(Operand.new(type: :register8, value: :e))
        when 0x04 then rlc8(Operand.new(type: :register8, value: :h))
        when 0x05 then rlc8(Operand.new(type: :register8, value: :l))
        when 0x06 then rlc8(Operand.new(type: :indirect, value: :hl))
        when 0x07 then rlc8(Operand.new(type: :register8, value: :a))
        when 0x08 then rrc8(Operand.new(type: :register8, value: :b))
        when 0x09 then rrc8(Operand.new(type: :register8, value: :c))
        when 0x0a then rrc8(Operand.new(type: :register8, value: :d))
        when 0x0b then rrc8(Operand.new(type: :register8, value: :e))
        when 0x0c then rrc8(Operand.new(type: :register8, value: :h))
        when 0x0d then rrc8(Operand.new(type: :register8, value: :l))
        when 0x0e then rrc8(Operand.new(type: :indirect, value: :hl))
        when 0x0f then rrc8(Operand.new(type: :register8, value: :a))
        when 0x10 then rl8(Operand.new(type: :register8, value: :b))
        when 0x11 then rl8(Operand.new(type: :register8, value: :c))
        when 0x12 then rl8(Operand.new(type: :register8, value: :d))
        when 0x13 then rl8(Operand.new(type: :register8, value: :e))
        when 0x14 then rl8(Operand.new(type: :register8, value: :h))
        when 0x15 then rl8(Operand.new(type: :register8, value: :l))
        when 0x16 then rl8(Operand.new(type: :indirect, value: :hl))
        when 0x17 then rl8(Operand.new(type: :register8, value: :a))
        when 0x18 then rr8(Operand.new(type: :register8, value: :b))
        when 0x19 then rr8(Operand.new(type: :register8, value: :c))
        when 0x1a then rr8(Operand.new(type: :register8, value: :d))
        when 0x1b then rr8(Operand.new(type: :register8, value: :e))
        when 0x1c then rr8(Operand.new(type: :register8, value: :h))
        when 0x1d then rr8(Operand.new(type: :register8, value: :l))
        when 0x1e then rr8(Operand.new(type: :indirect, value: :hl))
        when 0x1f then rr8(Operand.new(type: :register8, value: :a))
        when 0x20 then sla8(Operand.new(type: :register8, value: :b))
        when 0x21 then sla8(Operand.new(type: :register8, value: :c))
        when 0x22 then sla8(Operand.new(type: :register8, value: :d))
        when 0x23 then sla8(Operand.new(type: :register8, value: :e))
        when 0x24 then sla8(Operand.new(type: :register8, value: :h))
        when 0x25 then sla8(Operand.new(type: :register8, value: :l))
        when 0x26 then sla8(Operand.new(type: :indirect, value: :hl))
        when 0x27 then sla8(Operand.new(type: :register8, value: :a))
        when 0x28 then sra8(Operand.new(type: :register8, value: :b))
        when 0x29 then sra8(Operand.new(type: :register8, value: :c))
        when 0x2a then sra8(Operand.new(type: :register8, value: :d))
        when 0x2b then sra8(Operand.new(type: :register8, value: :e))
        when 0x2c then sra8(Operand.new(type: :register8, value: :h))
        when 0x2d then sra8(Operand.new(type: :register8, value: :l))
        when 0x2e then sra8(Operand.new(type: :indirect, value: :hl))
        when 0x2f then sra8(Operand.new(type: :register8, value: :a))
        when 0x30 then swap8(Operand.new(type: :register8, value: :b))
        when 0x31 then swap8(Operand.new(type: :register8, value: :c))
        when 0x32 then swap8(Operand.new(type: :register8, value: :d))
        when 0x33 then swap8(Operand.new(type: :register8, value: :e))
        when 0x34 then swap8(Operand.new(type: :register8, value: :h))
        when 0x35 then swap8(Operand.new(type: :register8, value: :l))
        when 0x36 then swap8(Operand.new(type: :indirect, value: :hl))
        when 0x37 then swap8(Operand.new(type: :register8, value: :a))
        when 0x38 then srl8(Operand.new(type: :register8, value: :b))
        when 0x39 then srl8(Operand.new(type: :register8, value: :c))
        when 0x3a then srl8(Operand.new(type: :register8, value: :d))
        when 0x3b then srl8(Operand.new(type: :register8, value: :e))
        when 0x3c then srl8(Operand.new(type: :register8, value: :h))
        when 0x3d then srl8(Operand.new(type: :register8, value: :l))
        when 0x3e then srl8(Operand.new(type: :indirect, value: :hl))
        when 0x3f then srl8(Operand.new(type: :register8, value: :a))
        when 0x40 then bit8(0, Operand.new(type: :register8, value: :b))
        when 0x41 then bit8(0, Operand.new(type: :register8, value: :c))
        when 0x42 then bit8(0, Operand.new(type: :register8, value: :d))
        when 0x43 then bit8(0, Operand.new(type: :register8, value: :e))
        when 0x44 then bit8(0, Operand.new(type: :register8, value: :h))
        when 0x45 then bit8(0, Operand.new(type: :register8, value: :l))
        when 0x46 then bit8(0, Operand.new(type: :indirect, value: :hl))
        when 0x47 then bit8(0, Operand.new(type: :register8, value: :a))
        when 0x48 then bit8(1, Operand.new(type: :register8, value: :b))
        when 0x49 then bit8(1, Operand.new(type: :register8, value: :c))
        when 0x4a then bit8(1, Operand.new(type: :register8, value: :d))
        when 0x4b then bit8(1, Operand.new(type: :register8, value: :e))
        when 0x4c then bit8(1, Operand.new(type: :register8, value: :h))
        when 0x4d then bit8(1, Operand.new(type: :register8, value: :l))
        when 0x4e then bit8(1, Operand.new(type: :indirect, value: :hl))
        when 0x4f then bit8(1, Operand.new(type: :register8, value: :a))
        when 0x50 then bit8(2, Operand.new(type: :register8, value: :b))
        when 0x51 then bit8(2, Operand.new(type: :register8, value: :c))
        when 0x52 then bit8(2, Operand.new(type: :register8, value: :d))
        when 0x53 then bit8(2, Operand.new(type: :register8, value: :e))
        when 0x54 then bit8(2, Operand.new(type: :register8, value: :h))
        when 0x55 then bit8(2, Operand.new(type: :register8, value: :l))
        when 0x56 then bit8(2, Operand.new(type: :indirect, value: :hl))
        when 0x57 then bit8(2, Operand.new(type: :register8, value: :a))
        when 0x58 then bit8(3, Operand.new(type: :register8, value: :b))
        when 0x59 then bit8(3, Operand.new(type: :register8, value: :c))
        when 0x5a then bit8(3, Operand.new(type: :register8, value: :d))
        when 0x5b then bit8(3, Operand.new(type: :register8, value: :e))
        when 0x5c then bit8(3, Operand.new(type: :register8, value: :h))
        when 0x5d then bit8(3, Operand.new(type: :register8, value: :l))
        when 0x5e then bit8(3, Operand.new(type: :indirect, value: :hl))
        when 0x5f then bit8(3, Operand.new(type: :register8, value: :a))
        when 0x60 then bit8(4, Operand.new(type: :register8, value: :b))
        when 0x61 then bit8(4, Operand.new(type: :register8, value: :c))
        when 0x62 then bit8(4, Operand.new(type: :register8, value: :d))
        when 0x63 then bit8(4, Operand.new(type: :register8, value: :e))
        when 0x64 then bit8(4, Operand.new(type: :register8, value: :h))
        when 0x65 then bit8(4, Operand.new(type: :register8, value: :l))
        when 0x66 then bit8(4, Operand.new(type: :indirect, value: :hl))
        when 0x67 then bit8(4, Operand.new(type: :register8, value: :a))
        when 0x68 then bit8(5, Operand.new(type: :register8, value: :b))
        when 0x69 then bit8(5, Operand.new(type: :register8, value: :c))
        when 0x6a then bit8(5, Operand.new(type: :register8, value: :d))
        when 0x6b then bit8(5, Operand.new(type: :register8, value: :e))
        when 0x6c then bit8(5, Operand.new(type: :register8, value: :h))
        when 0x6d then bit8(5, Operand.new(type: :register8, value: :l))
        when 0x6e then bit8(5, Operand.new(type: :indirect, value: :hl))
        when 0x6f then bit8(5, Operand.new(type: :register8, value: :a))
        when 0x70 then bit8(6, Operand.new(type: :register8, value: :b))
        when 0x71 then bit8(6, Operand.new(type: :register8, value: :c))
        when 0x72 then bit8(6, Operand.new(type: :register8, value: :d))
        when 0x73 then bit8(6, Operand.new(type: :register8, value: :e))
        when 0x74 then bit8(6, Operand.new(type: :register8, value: :h))
        when 0x75 then bit8(6, Operand.new(type: :register8, value: :l))
        when 0x76 then bit8(6, Operand.new(type: :indirect, value: :hl))
        when 0x77 then bit8(6, Operand.new(type: :register8, value: :a))
        when 0x78 then bit8(7, Operand.new(type: :register8, value: :b))
        when 0x79 then bit8(7, Operand.new(type: :register8, value: :c))
        when 0x7a then bit8(7, Operand.new(type: :register8, value: :d))
        when 0x7b then bit8(7, Operand.new(type: :register8, value: :e))
        when 0x7c then bit8(7, Operand.new(type: :register8, value: :h))
        when 0x7d then bit8(7, Operand.new(type: :register8, value: :l))
        when 0x7e then bit8(7, Operand.new(type: :indirect, value: :hl))
        when 0x7f then bit8(7, Operand.new(type: :register8, value: :a))
        when 0x80 then res8(0, Operand.new(type: :register8, value: :b))
        when 0x81 then res8(0, Operand.new(type: :register8, value: :c))
        when 0x82 then res8(0, Operand.new(type: :register8, value: :d))
        when 0x83 then res8(0, Operand.new(type: :register8, value: :e))
        when 0x84 then res8(0, Operand.new(type: :register8, value: :h))
        when 0x85 then res8(0, Operand.new(type: :register8, value: :l))
        when 0x86 then res8(0, Operand.new(type: :indirect, value: :hl))
        when 0x87 then res8(0, Operand.new(type: :register8, value: :a))
        when 0x88 then res8(1, Operand.new(type: :register8, value: :b))
        when 0x89 then res8(1, Operand.new(type: :register8, value: :c))
        when 0x8a then res8(1, Operand.new(type: :register8, value: :d))
        when 0x8b then res8(1, Operand.new(type: :register8, value: :e))
        when 0x8c then res8(1, Operand.new(type: :register8, value: :h))
        when 0x8d then res8(1, Operand.new(type: :register8, value: :l))
        when 0x8e then res8(1, Operand.new(type: :indirect, value: :hl))
        when 0x8f then res8(1, Operand.new(type: :register8, value: :a))
        when 0x90 then res8(2, Operand.new(type: :register8, value: :b))
        when 0x91 then res8(2, Operand.new(type: :register8, value: :c))
        when 0x92 then res8(2, Operand.new(type: :register8, value: :d))
        when 0x93 then res8(2, Operand.new(type: :register8, value: :e))
        when 0x94 then res8(2, Operand.new(type: :register8, value: :h))
        when 0x95 then res8(2, Operand.new(type: :register8, value: :l))
        when 0x96 then res8(2, Operand.new(type: :indirect, value: :hl))
        when 0x97 then res8(2, Operand.new(type: :register8, value: :a))
        when 0x98 then res8(3, Operand.new(type: :register8, value: :b))
        when 0x99 then res8(3, Operand.new(type: :register8, value: :c))
        when 0x9a then res8(3, Operand.new(type: :register8, value: :d))
        when 0x9b then res8(3, Operand.new(type: :register8, value: :e))
        when 0x9c then res8(3, Operand.new(type: :register8, value: :h))
        when 0x9d then res8(3, Operand.new(type: :register8, value: :l))
        when 0x9e then res8(3, Operand.new(type: :indirect, value: :hl))
        when 0x9f then res8(3, Operand.new(type: :register8, value: :a))
        when 0xa0 then res8(4, Operand.new(type: :register8, value: :b))
        when 0xa1 then res8(4, Operand.new(type: :register8, value: :c))
        when 0xa2 then res8(4, Operand.new(type: :register8, value: :d))
        when 0xa3 then res8(4, Operand.new(type: :register8, value: :e))
        when 0xa4 then res8(4, Operand.new(type: :register8, value: :h))
        when 0xa5 then res8(4, Operand.new(type: :register8, value: :l))
        when 0xa6 then res8(4, Operand.new(type: :indirect, value: :hl))
        when 0xa7 then res8(4, Operand.new(type: :register8, value: :a))
        when 0xa8 then res8(5, Operand.new(type: :register8, value: :b))
        when 0xa9 then res8(5, Operand.new(type: :register8, value: :c))
        when 0xaa then res8(5, Operand.new(type: :register8, value: :d))
        when 0xab then res8(5, Operand.new(type: :register8, value: :e))
        when 0xac then res8(5, Operand.new(type: :register8, value: :h))
        when 0xad then res8(5, Operand.new(type: :register8, value: :l))
        when 0xae then res8(5, Operand.new(type: :indirect, value: :hl))
        when 0xaf then res8(5, Operand.new(type: :register8, value: :a))
        when 0xb0 then res8(6, Operand.new(type: :register8, value: :b))
        when 0xb1 then res8(6, Operand.new(type: :register8, value: :c))
        when 0xb2 then res8(6, Operand.new(type: :register8, value: :d))
        when 0xb3 then res8(6, Operand.new(type: :register8, value: :e))
        when 0xb4 then res8(6, Operand.new(type: :register8, value: :h))
        when 0xb5 then res8(6, Operand.new(type: :register8, value: :l))
        when 0xb6 then res8(6, Operand.new(type: :indirect, value: :hl))
        when 0xb7 then res8(6, Operand.new(type: :register8, value: :a))
        when 0xb8 then res8(7, Operand.new(type: :register8, value: :b))
        when 0xb9 then res8(7, Operand.new(type: :register8, value: :c))
        when 0xba then res8(7, Operand.new(type: :register8, value: :d))
        when 0xbb then res8(7, Operand.new(type: :register8, value: :e))
        when 0xbc then res8(7, Operand.new(type: :register8, value: :h))
        when 0xbd then res8(7, Operand.new(type: :register8, value: :l))
        when 0xbe then res8(7, Operand.new(type: :indirect, value: :hl))
        when 0xbf then res8(7, Operand.new(type: :register8, value: :a))
        when 0xc0 then set8(0, Operand.new(type: :register8, value: :b))
        when 0xc1 then set8(0, Operand.new(type: :register8, value: :c))
        when 0xc2 then set8(0, Operand.new(type: :register8, value: :d))
        when 0xc3 then set8(0, Operand.new(type: :register8, value: :e))
        when 0xc4 then set8(0, Operand.new(type: :register8, value: :h))
        when 0xc5 then set8(0, Operand.new(type: :register8, value: :l))
        when 0xc6 then set8(0, Operand.new(type: :indirect, value: :hl))
        when 0xc7 then set8(0, Operand.new(type: :register8, value: :a))
        when 0xc8 then set8(1, Operand.new(type: :register8, value: :b))
        when 0xc9 then set8(1, Operand.new(type: :register8, value: :c))
        when 0xca then set8(1, Operand.new(type: :register8, value: :d))
        when 0xcb then set8(1, Operand.new(type: :register8, value: :e))
        when 0xcc then set8(1, Operand.new(type: :register8, value: :h))
        when 0xcd then set8(1, Operand.new(type: :register8, value: :l))
        when 0xce then set8(1, Operand.new(type: :indirect, value: :hl))
        when 0xcf then set8(1, Operand.new(type: :register8, value: :a))
        when 0xd0 then set8(2, Operand.new(type: :register8, value: :b))
        when 0xd1 then set8(2, Operand.new(type: :register8, value: :c))
        when 0xd2 then set8(2, Operand.new(type: :register8, value: :d))
        when 0xd3 then set8(2, Operand.new(type: :register8, value: :e))
        when 0xd4 then set8(2, Operand.new(type: :register8, value: :h))
        when 0xd5 then set8(2, Operand.new(type: :register8, value: :l))
        when 0xd6 then set8(2, Operand.new(type: :indirect, value: :hl))
        when 0xd7 then set8(2, Operand.new(type: :register8, value: :a))
        when 0xd8 then set8(3, Operand.new(type: :register8, value: :b))
        when 0xd9 then set8(3, Operand.new(type: :register8, value: :c))
        when 0xda then set8(3, Operand.new(type: :register8, value: :d))
        when 0xdb then set8(3, Operand.new(type: :register8, value: :e))
        when 0xdc then set8(3, Operand.new(type: :register8, value: :h))
        when 0xdd then set8(3, Operand.new(type: :register8, value: :l))
        when 0xde then set8(3, Operand.new(type: :indirect, value: :hl))
        when 0xdf then set8(3, Operand.new(type: :register8, value: :a))
        when 0xe0 then set8(4, Operand.new(type: :register8, value: :b))
        when 0xe1 then set8(4, Operand.new(type: :register8, value: :c))
        when 0xe2 then set8(4, Operand.new(type: :register8, value: :d))
        when 0xe3 then set8(4, Operand.new(type: :register8, value: :e))
        when 0xe4 then set8(4, Operand.new(type: :register8, value: :h))
        when 0xe5 then set8(4, Operand.new(type: :register8, value: :l))
        when 0xe6 then set8(4, Operand.new(type: :indirect, value: :hl))
        when 0xe7 then set8(4, Operand.new(type: :register8, value: :a))
        when 0xe8 then set8(5, Operand.new(type: :register8, value: :b))
        when 0xe9 then set8(5, Operand.new(type: :register8, value: :c))
        when 0xea then set8(5, Operand.new(type: :register8, value: :d))
        when 0xeb then set8(5, Operand.new(type: :register8, value: :e))
        when 0xec then set8(5, Operand.new(type: :register8, value: :h))
        when 0xed then set8(5, Operand.new(type: :register8, value: :l))
        when 0xee then set8(5, Operand.new(type: :indirect, value: :hl))
        when 0xef then set8(5, Operand.new(type: :register8, value: :a))
        when 0xf0 then set8(6, Operand.new(type: :register8, value: :b))
        when 0xf1 then set8(6, Operand.new(type: :register8, value: :c))
        when 0xf2 then set8(6, Operand.new(type: :register8, value: :d))
        when 0xf3 then set8(6, Operand.new(type: :register8, value: :e))
        when 0xf4 then set8(6, Operand.new(type: :register8, value: :h))
        when 0xf5 then set8(6, Operand.new(type: :register8, value: :l))
        when 0xf6 then set8(6, Operand.new(type: :indirect, value: :hl))
        when 0xf7 then set8(6, Operand.new(type: :register8, value: :a))
        when 0xf8 then set8(7, Operand.new(type: :register8, value: :b))
        when 0xf9 then set8(7, Operand.new(type: :register8, value: :c))
        when 0xfa then set8(7, Operand.new(type: :register8, value: :d))
        when 0xfb then set8(7, Operand.new(type: :register8, value: :e))
        when 0xfc then set8(7, Operand.new(type: :register8, value: :h))
        when 0xfd then set8(7, Operand.new(type: :register8, value: :l))
        when 0xfe then set8(7, Operand.new(type: :indirect, value: :hl))
        when 0xff then set8(7, Operand.new(type: :register8, value: :a))
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
      puts "PC: 0x#{'%04x' % @pc}, Opcode: 0x#{'%02x' % opcode}, AF: 0x#{'%04x' % @registers.read16(:af)}, BC: 0x#{'%04x' % @registers.read16(:bc)}, HL: 0x#{'%04x' % @registers.read16(:hl)}, SP: 0x#{'%04x' % @sp}"
    end

    def flags
      f_value = @registers.read8(:f)
      {
        z: f_value[7] == 1,
        n: f_value[6] == 1,
        h: f_value[5] == 1,
        c: f_value[4] == 1
      }
    end

    def update_flags(z: flags[:z], n: flags[:n], h: flags[:h], c: flags[:c])
      f_value = 0x00
      f_value |= 0x80 if z
      f_value |= 0x40 if n
      f_value |= 0x20 if h
      f_value |= 0x10 if c

      @registers.write8(:f, f_value)
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

    def rlca
      a_value = @registers.read8(:a)
      a_value = ((a_value << 1) | (a_value >> 7)) & 0xff
      @registers.write8(:a, a_value)
      update_flags(
        z: false,
        n: false,
        h: false,
        c: a_value[0] == 1
      )

      4
    end

    def rrca
      a_value = @registers.read8(:a)
      a_value = ((a_value >> 1) | (a_value << 7)) & 0xff
      @registers.write8(:a, a_value)
      update_flags(
        z: false,
        n: false,
        h: false,
        c: a_value[7] == 1
      )

      4
    end

    def rra
      a_value = @registers.read8(:a)
      cflag = a_value[0] == 1
      a_value = ((a_value >> 1) | (bool_to_integer(flags[:c]) << 7)) & 0xff
      @registers.write8(:a, a_value)
      update_flags(
        z: false,
        n: false,
        h: false,
        c: cflag
      )

      4
    end

    def rla
      a_value = @registers.read8(:a)
      cflag = a_value[7] == 1
      a_value = ((a_value << 1) | bool_to_integer(flags[:c])) & 0xff
      @registers.write8(:a, a_value)
      update_flags(
        z: false,
        n: false,
        h: false,
        c: cflag
      )

      4
    end

    def daa
      a_value = @registers.read8(:a)
      if flags[:n]
        a_value -= 0x06 if flags[:h]
        a_value -= 0x60 if flags[:c]
      else
        if flags[:c] || a_value > 0x99
          a_value += 0x60
          update_flags(c: true)
        end
        a_value += 0x06 if flags[:h] || (a_value & 0x0f) > 0x09
      end

      @registers.write8(:a, a_value)
      update_flags(
        z: @registers.read8(:a) == 0,
        h: false
      )

      4
    end

    def cpl
      @registers.write8(:a, ~@registers.read8(:a))
      update_flags(
        n: true,
        h: true
      )

      4
    end

    def scf
      update_flags(
        n: false,
        h: false,
        c: true
      )

      4
    end

    def ccf
      update_flags(
        n: false,
        h: false,
        c: !flags[:c]
      )

      4
    end

    def inc8(x)
      value = (get_value(x) + 1) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: (value & 0x0f) == 0
      )

      x.type == :register8 ? 4 : 12
    end

    def inc16(x)
      set_value(x, get_value(x) + 1)

      8
    end

    def dec8(x)
      value = (get_value(x) - 1) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: true,
        h: (value & 0x0f) == 0x0f
      )

      x.type == :register8 ? 4 : 12
    end

    def dec16(x)
      set_value(x, get_value(x) - 1)

      8
    end

    def add8(x)
      a_value = @registers.read8(:a)
      x_value = get_value(x)

      hflag = (a_value & 0x0f) + (x_value & 0x0f) > 0x0f
      cflag = a_value + x_value > 0xff

      a_value += x_value
      @registers.write8(:a, a_value)
      update_flags(
        z: @registers.read8(:a) == 0,
        n: false,
        h: hflag,
        c: cflag
      )

      x.type == :register8 ? 4 : 8
    end

    def add16(x, y)
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

      8
    end

    def add_sp_r8
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

      16
    end

    def sub8(x)
      a_value = @registers.read8(:a)
      x_value = get_value(x)

      hflag = (x_value & 0x0f) > (a_value & 0x0f)
      cflag = x_value > a_value
      a_value -= x_value
      @registers.write8(:a, a_value)
      update_flags(
        z: a_value == 0,
        n: true,
        h: hflag,
        c: cflag
      )

      x.type == :register8 ? 4 : 8
    end

    def adc8(x)
      a_value = @registers.read8(:a)
      x_value = get_value(x)
      c_value = bool_to_integer(flags[:c])

      hflag = (a_value & 0x0f) + (x_value & 0x0f) + c_value > 0x0f
      cflag = a_value + x_value + c_value > 0xff
      a_value += x_value + c_value
      @registers.write8(:a, a_value)
      update_flags(
        z: @registers.read8(:a) == 0,
        n: false,
        h: hflag,
        c: cflag
      )

      x.type == :register8 ? 4 : 8
    end

    def sbc8(x)
      a_value = @registers.read8(:a)
      x_value = get_value(x)
      c_value = bool_to_integer(flags[:c])

      hflag = (x_value & 0x0f) + c_value > (a_value & 0x0f)
      cflag = x_value + c_value > a_value
      a_value -= x_value + c_value
      @registers.write8(:a, a_value)
      update_flags(
        z: @registers.read8(:a) == 0,
        n: true,
        h: hflag,
        c: cflag
      )

      x.type == :register8 ? 4 : 8
    end

    def and8(x)
      a_value = @registers.read8(:a) & get_value(x)
      @registers.write8(:a, a_value)
      update_flags(
        z: a_value == 0,
        n: false,
        h: true,
        c: false
      )

      x.type == :register8 ? 4 : 8
    end

    def or8(x)
      a_value = @registers.read8(:a) | get_value(x)
      @registers.write8(:a, a_value)
      update_flags(
        z: a_value == 0,
        n: false,
        h: false,
        c: false
      )

      x.type == :register8 ? 4 : 8
    end

    def xor8(x)
      a_value = @registers.read8(:a) ^ get_value(x)
      @registers.write8(:a, a_value)
      update_flags(
        z: a_value == 0,
        n: false,
        h: false,
        c: false
      )

      x.type == :register8 ? 4 : 8
    end

    def push16(register16)
      value = @registers.read16(register16)
      @sp -= 2
      write_word(@sp, value)

      16
    end

    def pop16(register16)
      @registers.write16(register16, read_word(@sp))
      @sp += 2

      12
    end

    def halt
      @halted = true

      4
    end

    def ld8(x, y)
      value = get_value(y)
      set_value(x, value)

      return 4 if x.type == :register8 && y.type == :register8
      return 12 if x.type == :indirect && y.type == :immediate8
      return 12 if x.type == :ff00 || y.type == :ff00
      return 16 if x.type == :direct8 || y.type == :direct8

      8
    end

    def ld16(x, y)
      value = get_value(y)
      set_value(x, value)

      return 8 if y.type == :register16
      return 20 if y.type == :sp

      12
    end

    def ld_hl_sp_r8
      byte = to_signed_byte(read_byte_and_advance_pc)

      hflag = (@sp & 0x0f) + (byte & 0x0f) > 0x0f
      cflag = (@sp & 0xff) + (byte & 0xff) > 0xff
      @registers.write16(:hl, @sp + byte)
      update_flags(
        z: false,
        n: false,
        h: hflag,
        c: cflag
      )

      12
    end

    def ei
      @ime_delay = true

      4
    end

    def di
      @ime_delay = false
      @ime = false

      4
    end

    def cp8(x)
      a_value = @registers.read8(:a)
      x_value = get_value(x)

      hflag = (x_value & 0x0f) > (a_value & 0x0f)
      cflag = x_value > a_value
      update_flags(
        z: a_value == x_value,
        n: true,
        h: hflag,
        c: cflag
      )

      x.type == :register8 ? 4 : 8
    end

    def rst(addr)
      @sp -= 2
      write_word(@sp, @pc)
      @pc = addr

      16
    end

    def jr(condition: true)
      value = to_signed_byte(read_byte_and_advance_pc)
      @pc += value if condition

      condition ? 12 : 8
    end

    def jp(x, condition: true)
      addr = get_value(x)
      @pc = addr if condition

      return 4 if x.type == :register16

      condition ? 16 : 12
    end

    def call16(x, condition: true)
      addr = get_value(x)
      if condition
        @sp -= 2
        write_word(@sp, @pc)
        @pc = addr
      end

      condition ? 24 : 12
    end

    def ret
      @pc = read_word(@sp)
      @sp += 2

      16
    end

    def ret_if(condition)
      ret if condition

      condition ? 20 : 8
    end

    def reti
      @ime = true
      ret
    end

    def rlc8(x)
      value = get_value(x)
      value = (value << 1) | (value >> 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: value[0] == 1
      )

      x.type == :register8 ? 8 : 16
    end

    def rrc8(x)
      value = get_value(x)
      value = (value >> 1) | (value << 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: value[7] == 1
      )

      x.type == :register8 ? 8 : 16
    end

    def rl8(x)
      value = get_value(x)
      cflag = value[7] == 1
      value = ((value << 1) | bool_to_integer(flags[:c])) & 0xff
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      x.type == :register8 ? 8 : 16
    end

    def rr8(x)
      value = get_value(x)
      cflag = value[0] == 1
      value = (value >> 1) | (bool_to_integer(flags[:c]) << 7)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: cflag
      )

      x.type == :register8 ? 8 : 16
    end

    def sla8(x)
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

      x.type == :register8 ? 8 : 16
    end

    def sra8(x)
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

      x.type == :register8 ? 8 : 16
    end

    def swap8(x)
      value = get_value(x)
      value = ((value & 0x0f) << 4) | ((value & 0xf0) >> 4)
      set_value(x, value)
      update_flags(
        z: value == 0,
        n: false,
        h: false,
        c: false
      )

      x.type == :register8 ? 8 : 16
    end

    def srl8(x)
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

      x.type == :register8 ? 8 : 16
    end

    def bit8(n, x)
      value = get_value(x)
      update_flags(
        z: value[n] == 0,
        n: false,
        h: true
      )

      x.type == :register8 ? 8 : 12
    end

    def res8(n, x)
      value = get_value(x)
      value &= ((~(1 << n)) & 0xff)
      set_value(x, value)

      x.type == :register8 ? 8 : 16
    end

    def set8(n, x)
      value = get_value(x)
      value |= (1 << n)
      set_value(x, value)

      x.type == :register8 ? 8 : 16
    end

    def get_value(operand)
      case operand.type
      when :register8 then @registers.read8(operand.value)
      when :register16 then @registers.read16(operand.value)
      when :sp then @sp
      when :immediate8 then read_byte_and_advance_pc
      when :immediate16 then read_word_and_advance_pc
      when :direct8 then read_byte(read_word_and_advance_pc)
      when :direct16 then read_word(read_word_and_advance_pc)
      when :indirect then read_byte(@registers.read16(operand.value))
      when :ff00 then read_byte(0xff00 + read_byte_and_advance_pc)
      when :ff00_c then read_byte(0xff00 + @registers.read8(:c))
      when :hl_inc
        value = read_byte(@registers.read16(:hl))
        @registers.increment16(:hl)
        value
      when :hl_dec
        value = read_byte(@registers.read16(:hl))
        @registers.decrement16(:hl)
        value
      else raise "unknown operand: #{operand}"
      end
    end

    def set_value(operand, value)
      case operand.type
      when :register8 then @registers.write8(operand.value, value)
      when :register16 then @registers.write16(operand.value, value)
      when :sp then @sp = value & 0xffff
      when :direct8 then write_byte(read_word_and_advance_pc, value)
      when :direct16 then write_word(read_word_and_advance_pc, value)
      when :indirect then write_byte(@registers.read16(operand.value), value)
      when :ff00 then write_byte(0xff00 + read_byte_and_advance_pc, value)
      when :ff00_c then write_byte(0xff00 + @registers.read8(:c), value)
      when :hl_inc
        write_byte(@registers.read16(:hl), value)
        @registers.increment16(:hl)
      when :hl_dec
        write_byte(@registers.read16(:hl), value)
        @registers.decrement16(:hl)
      when :immediate8, :immediate16 then raise 'immediate type is read only'
      else raise "unknown operand: #{operand}"
      end
    end
  end
end
