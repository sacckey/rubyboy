# frozen_string_literal: true

module Rubyboy
  module Cartridge
    class Mbc1
      def initialize(rom, ram)
        @rom = rom
        @ram = ram
        @rom_bank = 1
        @ram_bank = 0
        @ram_enable = false
        @ram_banking_mode = false
      end

      def read_byte(addr)
        case (addr >> 12)
        when 0x0, 0x1, 0x2, 0x3
          @rom.data[addr]
        when 0x4, 0x5, 0x6, 0x7
          @rom.data[addr + ((@rom_bank - 1) << 14)]
        when 0xa, 0xb
          if @ram_enable
            if @ram_banking_mode
              @ram.eram[addr - 0xa000 + (@ram_bank << 11)]
            else
              @ram.eram[addr - 0xa000]
            end
          else
            0xff
          end
        end
      end

      def write_byte(addr, value)
        case addr >> 12
        when 0x0, 0x1
          @ram_enable = value & 0x0f == 0x0a
        when 0x2, 0x3
          @rom_bank = value & 0x1f
          @rom_bank = 1 if @rom_bank == 0
        when 0x4, 0x5
          @ram_bank = value & 0x03
        when 0x6, 0x7
          @ram_banking_mode = value & 0x01 == 0x01
        when 0xa, 0xb
          if @ram_enable
            if @ram_banking_mode
              @ram.eram[addr - 0xa000 + (@ram_bank << 11)] = value
            else
              @ram.eram[addr - 0xa000] = value
            end
          end
        end
      end
    end
  end
end
