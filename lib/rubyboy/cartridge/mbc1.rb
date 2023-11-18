# frozen_string_literal: true

require_relative '../ram'

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
        case addr
        when 0x0000..0x3fff
          @rom.data[addr]
        when 0x4000..0x7fff
          @rom.data[addr + (@rom_bank - 1) * 0x4000]
        when 0xa000..0xbfff
          if @ram_enable
            if @ram_banking_mode
              @ram.eram[addr - 0xa000 + @ram_bank * 0x800]
            else
              @ram.eram[addr - 0xa000]
            end
          else
            0xff
          end
        when 0xc000..0xcfff
          @ram.wram1[addr - 0xc000]
        when 0xd000..0xdfff
          @ram.wram2[addr - 0xd000]
        else
          raise "not implemented: read_byte #{addr}"
        end
      end

      def write_byte(addr, value)
        case addr
        when 0x0000..0x1fff
          @ram_enable = value & 0x0f == 0x0a
        when 0x2000..0x3fff
          @rom_bank = value & 0x1f
          @rom_bank = 1 if @rom_bank.zero?
        when 0x4000..0x5fff
          @ram_bank = value & 0x03
        when 0x6000..0x7fff
          @ram_banking_mode = value & 0x01 == 0x01
        when 0xa000..0xbfff
          if @ram_enable
            if @ram_banking_mode
              @ram.eram[addr - 0xa000 + @ram_bank * 0x800] = value
            else
              @ram.eram[addr - 0xa000] = value
            end
          end
        when 0xc000..0xcfff
          @ram.wram1[addr - 0xc000] = value
        when 0xd000..0xdfff
          @ram.wram2[addr - 0xd000] = value
        end
      end
    end
  end
end
