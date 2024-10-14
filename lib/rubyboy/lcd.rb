# frozen_string_literal: true

require 'rubyboy/sdl'

module Rubyboy
  class Lcd
    SCREEN_WIDTH = 160
    SCREEN_HEIGHT = 144
    SCALE = 3

    def initialize
      raise SDL.GetError() if SDL.InitSubSystem(SDL::INIT_VIDEO) != 0

      @buffer = FFI::MemoryPointer.new(:uint8, SCREEN_WIDTH * SCREEN_HEIGHT * 3)
      @window = SDL.CreateWindow('Ruby Boy', 0, 0, SCREEN_WIDTH * SCALE, SCREEN_HEIGHT * SCALE, SDL::SDL_WINDOW_RESIZABLE)

      raise SDL.GetError() if @window.null?

      @renderer = SDL.CreateRenderer(@window, -1, 0)
      SDL.SetHint('SDL_HINT_RENDER_SCALE_QUALITY', '2')
      SDL.RenderSetLogicalSize(@renderer, SCREEN_WIDTH * SCALE, SCREEN_HEIGHT * SCALE)
      @texture = SDL.CreateTexture(@renderer, SDL::PIXELFORMAT_RGB24, 1, SCREEN_WIDTH, SCREEN_HEIGHT)
      @event = FFI::MemoryPointer.new(:pointer)
    end

    def draw(framebuffer)
      @buffer.write_array_of_uint8(framebuffer)
      SDL.UpdateTexture(@texture, nil, @buffer, SCREEN_WIDTH * 3)
      SDL.RenderClear(@renderer)
      SDL.RenderCopy(@renderer, @texture, nil, nil)
      SDL.RenderPresent(@renderer)
    end

    def window_should_close?
      while SDL.PollEvent(@event) != 0
        event_type = @event.read_int
        return true if event_type == SDL::QUIT
      end

      false
    end

    def close_window
      SDL.DestroyWindow(@window)
      SDL.Quit
    end
  end
end
