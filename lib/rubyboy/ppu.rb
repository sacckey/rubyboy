# frozen_string_literal: true

module Rubyboy
  class Ppu
    attr_accessor :lcdc, :scy, :scx, :ly, :lyc, :bgp, :vram, :cycles

    def initialize
      @lcdc = 0x91
      @scy = 0x00
      @scx = 0x00
      @ly = 0x00
      @lyc = 0x00
      @bgp = 0xfc
      @vram = Array.new(8192, 0x00)
      @cycles = 0
    end

    def step(cycles)
      @cycles += cycles
      if @cycles >= 456
        @cycles -= 456
        @ly = (@ly + 1) % 154
      end
    end

    def draw_bg
      tile_map_addr = @lcdc[3] == 0 ? 0x9800 : 0x9c00
      tile_data_addr = @lcdc[4] == 0 ? 0x9000 : 0x8000

      bg = Array.new(256) { Array.new(256, 0x00) }

      32.times do |y|
        32.times do |x|
          tile_map_index = (y * 32 + x)
          tile_index = @vram[tile_map_addr - 0x8000 + tile_map_index]
          # TODO: if @lcdc[4] == 0 then the addr becomes signed

          tile = @vram[tile_data_addr - 0x8000 + tile_index * 16, 16]

          8.times do |i|
            pixelsa = tile[i*2]
            pixelsb = tile[i*2+1]

            8.times do |j|
              c = (pixelsb[7-j] << 1) + pixelsa[7-j]
              bg[y*8+i][x*8+j] = get_color(c)
            end
          end
        end
      end
      view_port = Array.new(144) { Array.new(160, 0x00) }

      144.times do |y|
        160.times do |x|
          view_port[y][x] = bg[(y+@scy) % 144][(x+@scx) % 160]
        end
      end
      view_port
    end

    private

    def get_color(color_num)
      case color_num
      when 0
        [0xff, 0xff, 0xff]
      when 1
        [0xcc, 0xcc, 0xcc]
      when 2
        [0x77, 0x77, 0x77]
      when 3
        [0x00, 0x00, 0x00]
      end
    end
  end
end
