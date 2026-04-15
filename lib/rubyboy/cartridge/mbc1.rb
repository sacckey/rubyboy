# frozen_string_literal: true

module Rubyboy
  module Cartridge
    class Mbc1
      ROM_BANK_SIZE = 0x4000
      RAM_BANK_SIZE = 0x2000

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
          @rom.data[rom_offset(addr)] || 0xff
        when 0x4, 0x5, 0x6, 0x7
          @rom.data[rom_offset(addr)] || 0xff
        when 0xa, 0xb
          return 0xff unless @ram_enable

          @ram.eram[ram_offset(addr)] || 0xff
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
          return unless @ram_enable

          offset = ram_offset(addr)
          @ram.eram[offset] = value if offset < @ram.eram.size
        end
      end

      private

      def rom_offset(addr)
        bank =
          if addr < ROM_BANK_SIZE
            @ram_banking_mode ? (@ram_bank << 5) : 0
          else
            (@ram_bank << 5) | @rom_bank
          end

        ((bank * ROM_BANK_SIZE) + (addr & (ROM_BANK_SIZE - 1))) % @rom.data.size
      end

      def ram_offset(addr)
        bank = @ram_banking_mode ? @ram_bank : 0
        (addr - 0xa000) + (bank * RAM_BANK_SIZE)
      end
    end
  end
end
