# frozen_string_literal: true

require_relative 'cartridge/factory'
require_relative 'interrupt'
require_relative 'timer'

module Rubyboy
  class Bus
    attr_accessor :ppu, :rom, :interrupt

    def initialize(ppu, rom, timer, interrupt)
      @ppu = ppu
      @rom = rom
      @ram = Ram.new
      @mbc = Cartridge::Factory.create(rom, @ram)

      @interrupt = interrupt
      @timer = timer

      @oam = Array.new(0xa0, 0)

      @tmp = {}
    end

    def read_byte(addr)
      case addr
      when 0x0000..0x7fff
        @mbc.read_byte(addr)
      when 0x8000..0x9fff
        @ppu.vram[addr - 0x8000]
      when 0xa000..0xdfff
        @mbc.read_byte(addr)
      when 0xe000..0xfdff
        # echo ram
      when 0xfe00..0xfe9f
        @oam[addr - 0xfe00]
      when 0xfea0..0xfeff
        # unused
        0xff
      when 0xff00
        # joypad
        @tmp[addr] ||= 0
      when 0xff01..0xff02
        # serial
        @tmp[addr] ||= 0
      when 0xff04..0xff07
        @timer.read_byte(addr)
      when 0xff0f
        @interrupt.if
      when 0xff10..0xff26
        # sound
        @tmp[addr] ||= 0
      when 0xff30..0xff3f
        # wave pattern ram
        @tmp[addr] ||= 0
      when 0xff40
        @ppu.lcdc
      when 0xff41
        # stat
        @tmp[addr] ||= 0
      when 0xff42
        @ppu.scy
      when 0xff43
        @ppu.scx
      when 0xff44
        @ppu.ly
      when 0xff45
        @ppu.lyc
      when 0xff46
        # dma
        @tmp[addr] ||= 0
      when 0xff47
        @ppu.bgp
      when 0xff48
        # obp0
        @tmp[addr] ||= 0
      when 0xff49
        # obp1
        @tmp[addr] ||= 0
      when 0xff4a
        # wy
        @tmp[addr] ||= 0
      when 0xff4b
        # wx
        @tmp[addr] ||= 0
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
        @interrupt.ie
      else
        0xff
      end
    end

    def write_byte(addr, value)
      case addr
      when 0x0000..0x7fff
        @mbc.write_byte(addr, value)
      when 0x8000..0x9fff
        @ppu.vram[addr - 0x8000] = value
      when 0xa000..0xdfff
        @mbc.write_byte(addr, value)
      when 0xe000..0xfdff
        # echo ram
      when 0xfe00..0xfe9f
        @oam[addr - 0xfe00] = value
      when 0xfea0..0xfeff
        # unused
      when 0xff00
        # joypad
        @tmp[addr] = value
      when 0xff01..0xff02
        # serial
        @tmp[addr] = value
      when 0xff04..0xff07
        @timer.write_byte(addr, value)
      when 0xff0f
        @interrupt.if = value
      when 0xff10..0xff26
        # sound
        @tmp[addr] = value
      when 0xff30..0xff3f
        # wave pattern ram
        @tmp[addr] = value
      when 0xff40
        @ppu.lcdc = value
      when 0xff41
        # stat
        @tmp[addr] = value
      when 0xff42
        @ppu.scy = value
      when 0xff43
        @ppu.scx = value
      when 0xff44
        @ppu.ly = value
      when 0xff45
        @ppu.lyc = value
      when 0xff46
        # dma
        @tmp[addr] = value
      when 0xff47
        @ppu.bgp = value
      when 0xff48
        # obp0
        @tmp[addr] = value
      when 0xff49
        # obp1
        @tmp[addr] = value
      when 0xff4a
        # wy
        @tmp[addr] = value
      when 0xff4b
        # wx
        @tmp[addr] = value
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
        @interrupt.ie = value
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
