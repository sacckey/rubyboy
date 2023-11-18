# frozen_string_literal: true

module Rubyboy
  class Ppu
    attr_reader :buffer

    MODE = {
      hblank: 0,
      vblank: 1,
      oam_scan: 2,
      drawing: 3
    }.freeze

    LCD_WIDTH = 160
    LCD_HEIGHT = 144

    OAM_SCAN_CYCLES = 80
    DRAWING_CYCLES = 172
    HBLANK_CYCLES = 204
    ONE_LINE_CYCLES = OAM_SCAN_CYCLES + DRAWING_CYCLES + HBLANK_CYCLES

    def initialize(interrupt)
      @mode = MODE[:oam_scan]
      @lcdc = 0x00
      @stat = 0x00
      @scy = 0x00
      @scx = 0x00
      @ly = 0x00
      @lyc = 0x00
      @obp0 = 0x00
      @obp1 = 0x00
      @wy = 0x00
      @wx = 0x00
      @bgp = 0x00
      @vram = Array.new(0x2000, 0x00)
      @oam = Array.new(0xa0, 0x00)
      @wly = 0x00
      @cycles = 0
      @interrupt = interrupt
      @buffer = Array.new(144 * 160, 0x00)
    end

    def read_byte(addr)
      case addr
      when 0x8000..0x9fff
        @mode == MODE[:drawing] ? 0xff : @vram[addr - 0x8000]
      when 0xfe00..0xfe9f
        @mode == MODE[:oam_scan] || @mode == MODE[:drawing] ? 0xff : @oam[addr - 0xfe00]
      when 0xff40
        @lcdc
      when 0xff41
        @stat | 0x80 | @mode
      when 0xff42
        @scy
      when 0xff43
        @scx
      when 0xff44
        @ly
      when 0xff45
        @lyc
      when 0xff47
        @bgp
      when 0xff48
        @obp0
      when 0xff49
        @obp1
      when 0xff4a
        @wy
      when 0xff4b
        @wx
      end
    end

    def write_byte(addr, value)
      case addr
      when 0x8000..0x9fff
        @vram[addr - 0x8000] = value if @mode != MODE[:drawing]
      when 0xfe00..0xfe9f
        @oam[addr - 0xfe00] = value if @mode != MODE[:oam_scan] && @mode != MODE[:drawing]
      when 0xff40
        @lcdc = value
      when 0xff41
        @stat = value & 0x78
      when 0xff42
        @scy = value
      when 0xff43
        @scx = value
      when 0xff44
        # ly is read only
      when 0xff45
        @lyc = value
      when 0xff46
        # dma
      when 0xff47
        @bgp = value
      when 0xff48
        @obp0 = value
      when 0xff49
        @obp1 = value
      when 0xff4a
        @wy = value
      when 0xff4b
        @wx = value
      end
    end

    def step(cycles)
      return false if @lcdc[7].zero?

      res = false
      @cycles += cycles

      case @mode
      when MODE[:oam_scan]
        if @cycles >= OAM_SCAN_CYCLES
          @cycles -= OAM_SCAN_CYCLES
          @mode = MODE[:drawing]
        end
      when MODE[:drawing]
        if @cycles >= DRAWING_CYCLES
          render_bg
          render_window
          render_sprites
          @cycles -= DRAWING_CYCLES
          @mode = MODE[:hblank]
          @interrupt.request(0b0000_0010) if @stat[3] == 1
        end
      when MODE[:hblank]
        if @cycles >= HBLANK_CYCLES
          @cycles -= HBLANK_CYCLES
          @ly += 1
          handle_ly_eq_lyc

          if @ly == LCD_HEIGHT
            @mode = MODE[:vblank]
            @interrupt.request(0b0000_0001)
            @interrupt.request(0b0000_0010) if @stat[4] == 1
          else
            @mode = MODE[:oam_scan]
            @interrupt.request(0b0000_0010) if @stat[5] == 1
          end
        end
      when MODE[:vblank]
        if @cycles >= ONE_LINE_CYCLES
          @cycles -= ONE_LINE_CYCLES
          @ly += 1
          handle_ly_eq_lyc

          if @ly == 154
            @ly = 0
            @wly = 0
            handle_ly_eq_lyc
            @mode = MODE[:oam_scan]
            @interrupt.request(0b0000_0010) if @stat[5] == 1
            res = true
          end
        end
      end

      res
    end

    def render_bg
      return if @lcdc[0].zero?

      y = (@ly + @scy) % 256
      LCD_WIDTH.times do |i|
        x = (i + @scx) % 256
        tile_index = get_tile_index(@lcdc[3], x, y)
        pixel = get_pixel(tile_index, x, y)
        @buffer[@ly * LCD_WIDTH + i] = get_color(@bgp, pixel)
      end
    end

    def render_window
      return if @lcdc[0].zero? || @lcdc[5].zero? || @ly < @wy

      rendered = false
      y = @wly
      LCD_WIDTH.times do |i|
        next if i < @wx - 7

        rendered = true
        x = i - (@wx - 7)
        tile_index = get_tile_index(@lcdc[6], x, y)
        pixel = get_pixel(tile_index, x, y)
        @buffer[@ly * LCD_WIDTH + i] = get_color(@bgp, pixel)
      end
      @wly += 1 if rendered
    end

    def render_sprites
      return if @lcdc[1].zero?

      sprite_height = @lcdc[2].zero? ? 8 : 16

      sprites = @oam.each_slice(4).filter_map do |sprite_attr|
        sprite = {
          y: (sprite_attr[0] - 16) % 256,
          x: (sprite_attr[1] - 8) % 256,
          tile_index: sprite_attr[2],
          flags: sprite_attr[3]
        }
        next if sprite[:y] > @ly || sprite[:y] + sprite_height <= @ly

        sprite
      end
      sprites.take(10).reverse.sort_by { _1[:x] }

      sprites.each do |sprite|
        pallet = sprite[:flags][4].zero? ? @obp0 : @obp1
        tile_index = sprite[:tile_index]
        tile_index &= 0xfe if sprite_height == 16
        y = (@ly - sprite[:y]) % 256
        y = sprite_height - y - 1 if sprite[:flags][6] == 1
        tile_index = (tile_index + 1) % 256 if y >= 8
        y %= 8

        8.times do |x|
          x_flipped = sprite[:flags][5] == 1 ? 7 - x : x

          pixel = get_pixel(tile_index, x_flipped, y)
          i = (sprite[:x] + x) % 256

          next if pixel.zero? || i >= LCD_WIDTH
          next if sprite[:flags][7] == 1 && @buffer[@ly * LCD_WIDTH + i] != 0xff

          @buffer[@ly * LCD_WIDTH + i] = get_color(pallet, pixel)
        end
      end
    end

    private

    def get_tile_index(tile_map_area, x, y)
      tile_map_addr = tile_map_area.zero? ? 0x1800 : 0x1c00
      tile_map_index = (y / 8) * 32 + (x / 8)
      tile_index = @vram[tile_map_addr + tile_map_index]
      @lcdc[4].zero? ? to_signed_byte(tile_index) + 256 : tile_index
    end

    def get_pixel(tile_index, x, y)
      @vram[tile_index * 16 + (y % 8) * 2][7 - (x % 8)] + (@vram[tile_index * 16 + (y % 8) * 2 + 1][7 - (x % 8)] << 1)
    end

    def get_color(pallet, pixel)
      case (pallet >> (pixel * 2)) & 0b11
      when 0 then 0xff
      when 1 then 0xaa
      when 2 then 0x55
      when 3 then 0x00
      end
    end

    def to_signed_byte(byte)
      byte &= 0xff
      byte > 127 ? byte - 256 : byte
    end

    def handle_ly_eq_lyc
      if @ly == @lyc
        @stat |= 0x04
        @interrupt.request(0b0000_0010) if @stat[6] == 1
      else
        @stat &= 0xfb
      end
    end
  end
end
