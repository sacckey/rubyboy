# frozen_string_literal: true

require 'raylib'

module Rubyboy
  class Lcd
    include Raylib

    WIDTH = 160
    HEIGHT = 144
    SCALE = 4

    def initialize
      load_raylib
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

    private

    def load_raylib
      shared_lib_path = "#{Gem::Specification.find_by_name('raylib-bindings').full_gem_path}/lib/"
      case RUBY_PLATFORM
      when /mswin|msys|mingw/ # Windows
        Raylib.load_lib("#{shared_lib_path}libraylib.dll")
      when /darwin/ # macOS
        Raylib.load_lib("#{shared_lib_path}libraylib.dylib")
      when /linux/ # Ubuntu Linux (x86_64 or aarch64)
        arch = RUBY_PLATFORM.split('-')[0]
        Raylib.load_lib(shared_lib_path + "libraylib.#{arch}.so")
      else
        raise "Unknown system: #{RUBY_PLATFORM}"
      end

      SetTraceLogLevel(LOG_ERROR)
    end
  end
end
