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

      @tmp = {}
    end

    def read_byte(addr)
      case addr
      when 0x0000..0x7fff
        @mbc.read_byte(addr)
      when 0x8000..0x9fff
        @ppu.read_byte(addr)
      when 0xa000..0xbfff
        @mbc.read_byte(addr)
      when 0xc000..0xcfff
        @ram.wram1[addr - 0xc000]
      when 0xd000..0xdfff
        @ram.wram2[addr - 0xd000]
      when 0xe000..0xfdff
        # echo ram
      when 0xfe00..0xfe9f
        @ppu.read_byte(addr)
      when 0xfea0..0xfeff
        # unused
        0xff
      when 0xff00
        @joypad.read_byte(addr)
      when 0xff01..0xff02
        # serial
        @tmp[addr] ||= 0
      when 0xff04..0xff07
        @timer.read_byte(addr)
      when 0xff0f
        @interrupt.read_byte(addr)
      when 0xff10..0xff26
        @apu.read_byte(addr)
      when 0xff30..0xff3f
        @apu.read_byte(addr)
      when 0xff40..0xff4b
        @ppu.read_byte(addr)
      when 0xff4f
        # vbk
        @tmp[addr] ||= 0
      when 0xff50
        # boot rom
        @tmp[addr] ||= 0
      when 0xff51..0xff55
        # hdma
        @tmp[addr] ||= 0
      when 0xff68..0xff6b
        # bgp
        @tmp[addr] ||= 0
      when 0xff70
        # svbk
        @tmp[addr] ||= 0
      when 0xff80..0xfffe
        @ram.hram[addr - 0xff80]
      when 0xffff
        @interrupt.read_byte(addr)
      else
        0xff
      end
    end

    def write_byte(addr, value)
      case addr
      when 0x0000..0x7fff
        @mbc.write_byte(addr, value)
      when 0x8000..0x9fff
        @ppu.write_byte(addr, value)
      when 0xa000..0xbfff
        @mbc.write_byte(addr, value)
      when 0xc000..0xcfff
        @ram.wram1[addr - 0xc000] = value
      when 0xd000..0xdfff
        @ram.wram2[addr - 0xd000] = value
      when 0xe000..0xfdff
        # echo ram
      when 0xfe00..0xfe9f
        @ppu.write_byte(addr, value)
      when 0xfea0..0xfeff
        # unused
      when 0xff00
        @joypad.write_byte(addr, value)
      when 0xff01..0xff02
        # serial
        @tmp[addr] = value
      when 0xff04..0xff07
        @timer.write_byte(addr, value)
      when 0xff0f
        @interrupt.write_byte(addr, value)
      when 0xff10..0xff26
        @apu.write_byte(addr, value)
      when 0xff30..0xff3f
        @apu.write_byte(addr, value)
      when 0xff46
        0xa0.times do |i|
          write_byte(0xfe00 + i, read_byte((value << 8) + i))
        end
      when 0xff40..0xff4b
        @ppu.write_byte(addr, value)
      when 0xff4f
        # vbk
        @tmp[addr] = value
      when 0xff50
        # boot rom
        @tmp[addr] = value
      when 0xff51..0xff55
        # hdma
        @tmp[addr] = value
      when 0xff68..0xff6b
        # bgp
        @tmp[addr] = value
      when 0xff70
        # svbk
        @tmp[addr] = value
      when 0xff80..0xfffe
        @ram.hram[addr - 0xff80] = value
      when 0xffff
        @interrupt.write_byte(addr, value)
      end
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
