# frozen_string_literal: true

module Rubyboy
  class Bus
    def initialize(ppu, rom, ram, mbc, timer, interrupt, joypad, apu)
      @ppu = ppu
      @rom = rom
      @ram = ram
      @mbc = mbc
      @joypad = joypad
      @apu = apu
      @interrupt = interrupt
      @timer = timer

      @read_methods = Array.new(0x10000)
      @write_methods = Array.new(0x10000)

      set_methods
    end

    def set_methods
      0x10000.times do |addr|
        case addr
        when 0x0000..0x7fff
          @read_methods[addr] = -> { @mbc.read_byte(addr) }
          @write_methods[addr] = ->(value) { @mbc.write_byte(addr, value) }
        when 0x8000..0x9fff
          @read_methods[addr] = -> { @ppu.read_byte(addr) }
          @write_methods[addr] = ->(value) { @ppu.write_byte(addr, value) }
        when 0xa000..0xbfff
          @read_methods[addr] = -> { @mbc.read_byte(addr) }
          @write_methods[addr] = ->(value) { @mbc.write_byte(addr, value) }
        when 0xc000..0xcfff
          @read_methods[addr] = -> { @ram.wram1[addr - 0xc000] }
          @write_methods[addr] = ->(value) { @ram.wram1[addr - 0xc000] = value }
        when 0xd000..0xdfff
          @read_methods[addr] = -> { @ram.wram2[addr - 0xd000] }
          @write_methods[addr] = ->(value) { @ram.wram2[addr - 0xd000] = value }
        when 0xfe00..0xfe9f
          @read_methods[addr] = -> { @ppu.read_byte(addr) }
          @write_methods[addr] = ->(value) { @ppu.write_byte(addr, value) }
        when 0xff00
          @read_methods[addr] = -> { @joypad.read_byte(addr) }
          @write_methods[addr] = ->(value) { @joypad.write_byte(addr, value) }
        when 0xff04..0xff07
          @read_methods[addr] = -> { @timer.read_byte(addr) }
          @write_methods[addr] = ->(value) { @timer.write_byte(addr, value) }
        when 0xff0f
          @read_methods[addr] = -> { @interrupt.read_byte(addr) }
          @write_methods[addr] = ->(value) { @interrupt.write_byte(addr, value) }
        when 0xff10..0xff26
          @read_methods[addr] = -> { @apu.read_byte(addr) }
          @write_methods[addr] = ->(value) { @apu.write_byte(addr, value) }
        when 0xff30..0xff3f
          @read_methods[addr] = -> { @apu.read_byte(addr) }
          @write_methods[addr] = ->(value) { @apu.write_byte(addr, value) }
        when 0xff46
          @read_methods[addr] = -> { @ppu.read_byte(addr) }
          @write_methods[addr] = ->(value) { 0xa0.times { |i| write_byte(0xfe00 + i, read_byte((value << 8) + i)) } }
        when 0xff40..0xff4b
          @read_methods[addr] = -> { @ppu.read_byte(addr) }
          @write_methods[addr] = ->(value) { @ppu.write_byte(addr, value) }
        when 0xff80..0xfffe
          @read_methods[addr] = -> { @ram.hram[addr - 0xff80] }
          @write_methods[addr] = ->(value) { @ram.hram[addr - 0xff80] = value }
        when 0xffff
          @read_methods[addr] = -> { @interrupt.read_byte(addr) }
          @write_methods[addr] = ->(value) { @interrupt.write_byte(addr, value) }
        else
          @read_methods[addr] = -> { 0xff }
          @write_methods[addr] = ->(_value) { }
        end
      end
    end

    def read_byte(addr)
      @read_methods[addr].call
    end

    def write_byte(addr, value)
      @write_methods[addr].call(value)
    end

    def read_word(addr)
      read_byte(addr) + (read_byte(addr + 1) << 8)
    end

    def write_word(addr, value)
      write_byte(addr, value & 0xff)
      write_byte(addr + 1, value >> 8)
    end
  end
end
