# frozen_string_literal: true

module Rubyboy
  class Ppu
    attr_reader :buffer

    PIXEL_FORMATS = {
      rgb: 3,
      rgba: 4
    }.freeze

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

    def initialize(interrupt, pixel_format = :rgb)
      raise ArgumentError, 'Invalid pixel format' unless PIXEL_FORMATS.key?(pixel_format)

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
      @channel_count = PIXEL_FORMATS[pixel_format]
      @buffer = Array.new(144 * 160, 0xffffffff)
      @bg_pixels = Array.new(LCD_WIDTH, 0x00)
      @tile_cache = Array.new(384) { Array.new(64, 0) }
      @tile_map_cache = Array.new(2048, 0)
      @bgp_cache = Array.new(4, 0xffffffff)
      @obp0_cache = Array.new(4, 0xffffffff)
      @obp1_cache = Array.new(4, 0xffffffff)
      @sprite_cache = Array.new(40) { { y: 0xff, x: 0xff, tile_index: 0, flags: 0 } }
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
        if @mode != MODE[:drawing]
          @vram[addr - 0x8000] = value
          if addr < 0x9800
            update_tile_cache(addr - 0x8000)
          else
            update_tile_map_cache(addr - 0x8000)
          end
        end
      when 0xfe00..0xfe9f
        if @mode != MODE[:oam_scan] && @mode != MODE[:drawing]
          @oam[addr - 0xfe00] = value
          sprite_index = (addr - 0xfe00) >> 2
          attribute = (addr - 0xfe00) & 3

          case attribute
          when 0 then @sprite_cache[sprite_index][:y] = (value - 16) & 0xff
          when 1 then @sprite_cache[sprite_index][:x] = (value - 8) & 0xff
          when 2 then @sprite_cache[sprite_index][:tile_index] = value
          when 3 then @sprite_cache[sprite_index][:flags] = value
          end
        end
      when 0xff40
        old_lcdc = @lcdc
        @lcdc = value

        if old_lcdc[LCDC[:bg_window_tile_data_area]] != @lcdc[LCDC[:bg_window_tile_data_area]]
          refresh_tile_map_cache
        end
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
        refresh_palette_cache(@bgp_cache, value)
      when 0xff48
        @obp0 = value
        refresh_palette_cache(@obp0_cache, value)
      when 0xff49
        @obp1 = value
        refresh_palette_cache(@obp1_cache, value)
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

      y = (@ly + @scy) & 0xff
      tile_map_addr = (y >> 3) << 5
      tile_map_addr += 1024 if @lcdc[LCDC[:bg_tile_map_area]] == 1
      tile_y = (y & 7) << 3
      buffer_start_index = @ly * LCD_WIDTH

      scx = @scx
      buffer = @buffer
      bg_pixels = @bg_pixels
      tile_cache = @tile_cache
      tile_map_cache = @tile_map_cache
      bgp_cache = @bgp_cache

      i = 0
      current_tile = scx >> 3
      x_offset = scx & 7

      if x_offset > 0
        tile = tile_cache[tile_map_cache[tile_map_addr + current_tile]]
        while (x_offset + i) < 8
          pixel = tile[tile_y + x_offset + i]
          buffer[buffer_start_index + i] = bgp_cache[pixel]
          bg_pixels[i] = pixel
          i += 1
        end
        current_tile += 1
      end

      while i < LCD_WIDTH - 7
        tile = tile_cache[tile_map_cache[tile_map_addr + (current_tile & 0x1f)]]
        idx = buffer_start_index + i

        # Unroll the 8-pixel loop
        pixel = tile[tile_y]
        buffer[idx] = bgp_cache[pixel]
        bg_pixels[i] = pixel

        pixel = tile[tile_y + 1]
        buffer[idx + 1] = bgp_cache[pixel]
        bg_pixels[i + 1] = pixel

        pixel = tile[tile_y + 2]
        buffer[idx + 2] = bgp_cache[pixel]
        bg_pixels[i + 2] = pixel

        pixel = tile[tile_y + 3]
        buffer[idx + 3] = bgp_cache[pixel]
        bg_pixels[i + 3] = pixel

        pixel = tile[tile_y + 4]
        buffer[idx + 4] = bgp_cache[pixel]
        bg_pixels[i + 4] = pixel

        pixel = tile[tile_y + 5]
        buffer[idx + 5] = bgp_cache[pixel]
        bg_pixels[i + 5] = pixel

        pixel = tile[tile_y + 6]
        buffer[idx + 6] = bgp_cache[pixel]
        bg_pixels[i + 6] = pixel

        pixel = tile[tile_y + 7]
        buffer[idx + 7] = bgp_cache[pixel]
        bg_pixels[i + 7] = pixel

        i += 8
        current_tile += 1
      end

      if i < LCD_WIDTH
        tile = tile_cache[tile_map_cache[tile_map_addr + (current_tile & 0x1f)]]
        x = 0
        while i < LCD_WIDTH
          pixel = tile[tile_y + x]
          buffer[buffer_start_index + i] = bgp_cache[pixel]
          bg_pixels[i] = pixel
          x += 1
          i += 1
        end
      end
    end

    def render_window
      return if @lcdc[LCDC[:bg_window_enable]] == 0 || @lcdc[LCDC[:window_enable]] == 0 || @ly < @wy

      rendered = false
      y = @wly
      tile_map_addr = (y >> 3) << 5
      tile_map_addr += 1024 if @lcdc[LCDC[:window_tile_map_area]] == 1
      tile_y = (y & 7) << 3
      buffer_start_index = @ly * LCD_WIDTH
      LCD_WIDTH.times do |i|
        next if i < @wx - 7

        rendered = true
        x = i - (@wx - 7)
        tile_index = @tile_map_cache[tile_map_addr + (x >> 3)]
        pixel = @tile_cache[tile_index][tile_y + (x & 7)]
        @buffer[buffer_start_index + i] = @bgp_cache[pixel]
        @bg_pixels[i] = pixel
      end
      @wly += 1 if rendered
    end

    def render_sprites
      return if @lcdc[LCDC[:sprite_enable]] == 0

      sprite_height = @lcdc[LCDC[:sprite_size]] == 0 ? 8 : 16
      sprites = []
      cnt = 0

      @sprite_cache.each do |sprite|
        next if sprite[:y] > @ly || sprite[:y] + sprite_height <= @ly

        sprites << sprite
        cnt += 1
        break if cnt == 10
      end
      sprites.reverse!
      sprites.sort! { |a, b| b[:x] <=> a[:x] }

      sprites.each do |sprite|
        flags = sprite[:flags]
        pallet = flags[SPRITE_FLAGS[:dmg_palette]] == 0 ? @obp0_cache : @obp1_cache
        tile_index = sprite[:tile_index]
        tile_index &= 0xfe if sprite_height == 16
        y = (@ly - sprite[:y]) & 0xff
        y = sprite_height - y - 1 if flags[SPRITE_FLAGS[:y_flip]] == 1
        tile_index = (tile_index + 1) & 0xff if y >= 8
        tile_y = (y & 7) << 3
        buffer_start_index = @ly * LCD_WIDTH

        8.times do |x|
          x_flipped = flags[SPRITE_FLAGS[:x_flip]] == 1 ? 7 - x : x

          pixel = @tile_cache[tile_index][tile_y + x_flipped]
          i = (sprite[:x] + x) & 0xff

          next if pixel == 0 || i >= LCD_WIDTH
          next if flags[SPRITE_FLAGS[:priority]] == 1 && @bg_pixels[i] != 0

          @buffer[buffer_start_index + i] = pallet[pixel]
        end
      end
    end

    private

    def update_tile_cache(addr)
      tile_index = addr >> 4

      row = (addr & 0xf) >> 1
      return if row >= 8

      byte1 = @vram[addr & ~1]
      byte2 = @vram[addr | 1]

      8.times do |col|
        bit_index = 7 - col
        pixel = ((byte1 >> bit_index) & 1) | (((byte2 >> bit_index) & 1) << 1)
        @tile_cache[tile_index][(row << 3) + col] = pixel
      end
    end

    def update_tile_map_cache(addr)
      map_index = addr - 0x1800
      tile_index = @vram[addr]
      @tile_map_cache[map_index] = @lcdc[LCDC[:bg_window_tile_data_area]] == 0 ?
        to_signed_byte(tile_index) + 256 :
        tile_index
    end

    def refresh_tile_map_cache
      is_8800_mode = @lcdc[LCDC[:bg_window_tile_data_area]] == 0

      (0x1800..0x1fff).each do |addr|
        @tile_map_cache[addr - 0x1800] = is_8800_mode ? to_signed_byte(@vram[addr]) + 256 : @vram[addr]
      end
    end

    def refresh_palette_cache(cache, palette_value)
      4.times do |i|
        case (palette_value >> (i << 1)) & 0b11
        when 0 then cache[i] = 0xffffffff
        when 1 then cache[i] = 0xffaaaaaa
        when 2 then cache[i] = 0xff555555
        when 3 then cache[i] = 0xff000000
        end
      end
    end

    def get_color(pallet, pixel)
      case (pallet >> (pixel << 1)) & 0b11
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
