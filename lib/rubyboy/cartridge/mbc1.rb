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

        @read_methods = Array.new(0xc000)
        @write_methods = Array.new(0xc000)

        set_methods
      end

      def set_methods
        0xc.times do |prefix|
          @read_methods[prefix] =
            case prefix
            when 0x0..0x3 then ->(addr) { @rom.data[addr] }
            when 0x4..0x7 then ->(addr) { @rom.data[addr + (@rom_bank - 1) * 0x4000] }
            when 0xa..0xb
              lambda do |addr|
                if @ram_enable
                  if @ram_banking_mode
                    @ram.eram[addr - 0xa000 + @ram_bank * 0x800]
                  else
                    @ram.eram[addr - 0xa000]
                  end
                else
                  0xff
                end
              end
            end
        end

        0xc.times do |prefix|
          @write_methods[prefix] =
            case prefix
            when 0x0..0x1 then ->(_addr, value) { @ram_enable = value & 0x0f == 0x0a }
            when 0x2..0x3
              lambda do |_addr, value|
                @rom_bank = value & 0x1f
                @rom_bank = 1 if @rom_bank == 0
              end
            when 0x4..0x5 then ->(_addr, value) { @ram_bank = value & 0x03 }
            when 0x6..0x7 then ->(_addr, value) { @ram_banking_mode = value & 0x01 == 0x01 }
            when 0xa..0xb
              lambda do |addr, value|
                if @ram_enable
                  if @ram_banking_mode
                    @ram.eram[addr - 0xa000 + @ram_bank * 0x800] = value
                  else
                    @ram.eram[addr - 0xa000] = value
                  end
                end
              end
            end
        end
      end

      def read_byte(addr)
        @read_methods[addr >> 12].call(addr)
      end

      def write_byte(addr, value)
        @write_methods[addr >> 12].call(addr, value)
      end
    end
  end
end
