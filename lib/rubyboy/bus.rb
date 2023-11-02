# frozen_string_literal: true

module Rubyboy
  class Bus
    attr_accessor :ppu, :rom

    def initialize(ppu, rom)
      @ppu = ppu
      @rom = rom
    end

    def read_byte(addr)
      case addr
      when 0x0000..0x7fff
        @rom.data[addr]
      when 0x8000..0x9fff
        @ppu.vram[addr - 0x8000]
      when 0xff26
        # nr52
      when 0xff40
        @ppu.lcdc
      when 0xff42
        @ppu.scy
      when 0xff43
        @ppu.scx
      when 0xff44
        @ppu.ly
      when 0xff47
        @ppu.bgp
      else
        raise "not implemented: write_byte #{addr}"
      end
    end

    def write_byte(addr, value)
      case addr
      when 0x0000..0x7fff
        @rom.data[addr] = value
      when 0x8000..0x9fff
        @ppu.vram[addr - 0x8000] = value
      when 0xff26
        # nr52
      when 0xff40
        @ppu.lcdc = value
      when 0xff42
        @ppu.scy = value
      when 0xff43
        @ppu.scx = value
      when 0xff44
        @ppu.ly = value
      when 0xff47
        @ppu.bgp = value
      else
        raise "not implemented: write_byte #{addr}"
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
