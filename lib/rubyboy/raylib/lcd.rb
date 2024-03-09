# frozen_string_literal: true

require 'raylib'

module Rubyboy
  module Raylib
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
        @vector = Vector2.create(0, 0)
      end

      def draw(pixel_data)
        UpdateTexture(@texture, pixel_data.pack('C*'))

        BeginDrawing()
        ClearBackground(BLACK)
        DrawTextureEx(@texture, @vector, 0.0, SCALE, WHITE)
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
end
