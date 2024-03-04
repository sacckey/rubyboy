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
        0xc000.times do |addr|
          @read_methods[addr] =
            case addr
            when 0x0000..0x3fff then -> { @rom.data[addr] }
            when 0x4000..0x7fff then -> { @rom.data[addr + (@rom_bank - 1) * 0x4000] }
            when 0xa000..0xbfff
              lambda do
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

        0xc000.times do |addr|
          @write_methods[addr] =
            case addr
            when 0x0000..0x1fff then ->(value) { @ram_enable = value & 0x0f == 0x0a }
            when 0x2000..0x3fff
              lambda do |value|
                @rom_bank = value & 0x1f
                @rom_bank = 1 if @rom_bank == 0
              end
            when 0x4000..0x5fff then ->(value) { @ram_bank = value & 0x03 }
            when 0x6000..0x7fff then ->(value) { @ram_banking_mode = value & 0x01 == 0x01 }
            when 0xa000..0xbfff
              lambda do |value|
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
        @read_methods[addr].call
      end

      def write_byte(addr, value)
        @write_methods[addr].call(value)
      end
    end
  end
end
