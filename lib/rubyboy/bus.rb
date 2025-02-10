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
    end

    def read_byte(addr)
      case addr >> 12
      when 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0xa, 0xb
        return @mbc.read_byte(addr)
      when 0x8, 0x9
        return @ppu.read_byte(addr)
      when 0xc
        return @ram.wram1[addr - 0xc000]
      when 0xd
        return @ram.wram2[addr - 0xd000]
      when 0xf
        case addr >> 8
        when 0xfe
          return @ppu.read_byte(addr) if addr <= 0xfe9f
        when 0xff
          last_byte = addr & 0xFF

          case last_byte
          when 0x00
            return @joypad.read_byte(addr)
          when 0x04, 0x05, 0x06, 0x07
            return @timer.read_byte(addr)
          when 0x0f
            return @interrupt.read_byte(addr)
          when 0x46
            return @ppu.read_byte(addr)
          when 0xff
            return @interrupt.read_byte(addr)
          end

          return @apu.read_byte(addr) if last_byte <= 0x26 && last_byte >= 0x10

          return @apu.read_byte(addr) if last_byte <= 0x3f && last_byte >= 0x30

          return @ppu.read_byte(addr) if last_byte <= 0x4b && last_byte >= 0x40

          return @ram.hram[addr - 0xff80] if last_byte <= 0xfe && last_byte >= 0x80
        end
      end

      0xff
    end

    def write_byte(addr, value)
      case addr >> 12
      when 0x0, 0x1, 0x2, 0x3, 0x4, 0x5, 0x6, 0x7, 0xa, 0xb
        return @mbc.write_byte(addr, value)
      when 0x8, 0x9
        return @ppu.write_byte(addr, value)
      when 0xc
        return @ram.wram1[addr - 0xc000] = value
      when 0xd
        return @ram.wram2[addr - 0xd000] = value
      when 0xf
        case addr >> 8
        when 0xfe
          return @ppu.write_byte(addr, value) if addr <= 0xfe9f
        when 0xff
          last_byte = addr & 0xFF

          case last_byte
          when 0x00
            return @joypad.write_byte(addr, value)
          when 0x04, 0x05, 0x06, 0x07
            return @timer.write_byte(addr, value)
          when 0x0f
            return @interrupt.write_byte(addr, value)
          when 0x46
            0xa0.times { |i| write_byte(0xfe00 + i, read_byte((value << 8) + i)) }
            return
          when 0xff
            return @interrupt.write_byte(addr, value)
          end

          return @apu.write_byte(addr, value) if last_byte <= 0x26 && last_byte >= 0x10

          return @apu.write_byte(addr, value) if last_byte <= 0x3f && last_byte >= 0x30

          return @ppu.write_byte(addr, value) if last_byte <= 0x4b && last_byte >= 0x40

          return @ram.hram[addr - 0xff80] = value if last_byte <= 0xfe && last_byte >= 0x80
        end
      end

      nil
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
