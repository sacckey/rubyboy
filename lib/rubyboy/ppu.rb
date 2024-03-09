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

    LCDC = {
      bg_window_enable: 0,
      sprite_enable: 1,
      sprite_size: 2,
      bg_tile_map_area: 3,
      bg_window_tile_data_area: 4,
      window_enable: 5,
      window_tile_map_area: 6,
      lcd_ppu_enable: 7
    }.freeze

    STAT = {
      ly_eq_lyc: 2,
      hblank: 3,
      vblank: 4,
      oam_scan: 5,
      lyc: 6
    }.freeze

    SPRITE_FLAGS = {
      bank: 3,
      dmg_palette: 4,
      x_flip: 5,
      y_flip: 6,
      priority: 7
    }.freeze

    LCD_WIDTH = 160
    LCD_HEIGHT = 144

    OAM_SCAN_CYCLES = 80
    DRAWING_CYCLES = 172
    HBLANK_CYCLES = 204
    ONE_LINE_CYCLES = OAM_SCAN_CYCLES + DRAWING_CYCLES + HBLANK_CYCLES

    def initialize(interrupt)
      @mode = MODE[:oam_scan]
      @lcdc = 0x91
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
      @buffer = Array.new(144 * 160 * 3, 0x00)
      @bg_pixels = Array.new(LCD_WIDTH, 0x00)
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
      return false if @lcdc[LCDC[:lcd_ppu_enable]] == 0

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
          @interrupt.request(:lcd) if @stat[STAT[:hblank]] == 1
        end
      when MODE[:hblank]
        if @cycles >= HBLANK_CYCLES
          @cycles -= HBLANK_CYCLES
          @ly += 1
          handle_ly_eq_lyc

          if @ly == LCD_HEIGHT
            @mode = MODE[:vblank]
            @interrupt.request(:vblank)
            @interrupt.request(:lcd) if @stat[STAT[:vblank]] == 1
          else
            @mode = MODE[:oam_scan]
            @interrupt.request(:lcd) if @stat[STAT[:oam_scan]] == 1
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
            @interrupt.request(:lcd) if @stat[STAT[:oam_scan]] == 1
            res = true
          end
        end
      end

      res
    end

    def render_bg
      return if @lcdc[LCDC[:bg_window_enable]] == 0

      y = (@ly + @scy) % 256
      tile_map_addr = @lcdc[LCDC[:bg_tile_map_area]] == 0 ? 0x1800 : 0x1c00
      tile_map_addr += (y / 8) * 32
      LCD_WIDTH.times do |i|
        x = (i + @scx) % 256
        tile_index = get_tile_index(tile_map_addr + (x / 8))
        pixel = get_pixel(tile_index << 4, 7 - (x % 8), (y % 8) * 2)
        color = get_color(@bgp, pixel)
        base = @ly * LCD_WIDTH * 3 + i * 3
        @buffer[base] = color
        @buffer[base + 1] = color
        @buffer[base + 2] = color
        @bg_pixels[i] = pixel
      end
    end

    def render_window
      return if @lcdc[LCDC[:bg_window_enable]] == 0 || @lcdc[LCDC[:window_enable]] == 0 || @ly < @wy

      rendered = false
      y = @wly
      tile_map_addr = @lcdc[LCDC[:window_tile_map_area]] == 0 ? 0x1800 : 0x1c00
      tile_map_addr += (y / 8) * 32
      LCD_WIDTH.times do |i|
        next if i < @wx - 7

        rendered = true
        x = i - (@wx - 7)
        tile_index = get_tile_index(tile_map_addr + (x / 8))
        pixel = get_pixel(tile_index << 4, 7 - (x % 8), (y % 8) * 2)
        color = get_color(@bgp, pixel)
        base = @ly * LCD_WIDTH * 3 + i * 3
        @buffer[base] = color
        @buffer[base + 1] = color
        @buffer[base + 2] = color
        @bg_pixels[i] = pixel
      end
      @wly += 1 if rendered
    end

    def render_sprites
      return if @lcdc[LCDC[:sprite_enable]] == 0

      sprite_height = @lcdc[LCDC[:sprite_size]] == 0 ? 8 : 16
      sprites = []
      cnt = 0

      @oam.each_slice(4) do |y, x, tile_index, flags|
        y = (y - 16) % 256
        x = (x - 8) % 256
        next if y > @ly || y + sprite_height <= @ly

        sprites << { y:, x:, tile_index:, flags: }
        cnt += 1
        break if cnt == 10
      end
      sprites = sprites.sort_by.with_index { |sprite, i| [-sprite[:x], -i] }

      sprites.each do |sprite|
        flags = sprite[:flags]
        pallet = flags[SPRITE_FLAGS[:dmg_palette]] == 0 ? @obp0 : @obp1
        tile_index = sprite[:tile_index]
        tile_index &= 0xfe if sprite_height == 16
        y = (@ly - sprite[:y]) % 256
        y = sprite_height - y - 1 if flags[SPRITE_FLAGS[:y_flip]] == 1
        tile_index = (tile_index + 1) % 256 if y >= 8
        y %= 8

        8.times do |x|
          x_flipped = flags[SPRITE_FLAGS[:x_flip]] == 1 ? 7 - x : x

          pixel = get_pixel(tile_index << 4, 7 - x_flipped, (y % 8) * 2)
          i = (sprite[:x] + x) % 256

          next if pixel == 0 || i >= LCD_WIDTH
          next if flags[SPRITE_FLAGS[:priority]] == 1 && @bg_pixels[i] != 0

          color = get_color(pallet, pixel)
          base = @ly * LCD_WIDTH * 3 + i * 3
          @buffer[base] = color
          @buffer[base + 1] = color
          @buffer[base + 2] = color
        end
      end
    end

    private

    def get_tile_index(tile_map_addr)
      tile_index = @vram[tile_map_addr]
      @lcdc[LCDC[:bg_window_tile_data_area]] == 0 ? to_signed_byte(tile_index) + 256 : tile_index
    end

    def get_pixel(tile_index, c, r)
      @vram[tile_index + r][c] + (@vram[tile_index + r + 1][c] << 1)
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
        @interrupt.request(:lcd) if @stat[STAT[:lyc]] == 1
      else
        @stat &= 0xfb
      end
    end
  end
end
