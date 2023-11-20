# frozen_string_literal: true

require 'raylib'

module Rubyboy
  class Lcd
    include Raylib

    WIDTH = 160
    HEIGHT = 144
    SCALE = 4

    def initialize
      InitWindow(WIDTH * SCALE, HEIGHT * SCALE, 'RUBY BOY')
      image = GenImageColor(WIDTH, HEIGHT, BLACK)
      image.format = PIXELFORMAT_UNCOMPRESSED_R8G8B8
      @texture = LoadTextureFromImage(image)
    end

    def draw(pixel_data)
      UpdateTexture(@texture, pixel_data)

      BeginDrawing()
      ClearBackground(BLACK)
      DrawTextureEx(@texture, Vector2.create(0, 0), 0.0, SCALE, WHITE)
      EndDrawing()
    end

    def window_should_close?
      WindowShouldClose()
    end

    def close_window
      CloseWindow()
    end
  end
end
