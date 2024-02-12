require 'ffi'

module Rubyboy
  module SDL
    extend FFI::Library
    ffi_lib 'SDL2'

    INIT_TIMER = 0x01
    INIT_VIDEO = 0x20
    INIT_KEYBOARD = 0x200
    WINDOW_RESIZABLE = 0x20
    PIXELFORMAT_RGB24 = 386930691
    SDL_WINDOW_RESIZABLE = 0x20

    SDL_SCANCODE_W = 26
    SDL_SCANCODE_A = 4
    SDL_SCANCODE_S = 22
    SDL_SCANCODE_D = 7
    SDL_SCANCODE_J = 13
    SDL_SCANCODE_K = 14
    SDL_SCANCODE_U = 24
    SDL_SCANCODE_I = 12

    attach_function :Init, 'SDL_Init', [:uint32], :int
    attach_function :InitSubSystem, 'SDL_InitSubSystem', [ :uint32 ], :int
    attach_function :CreateWindow, 'SDL_CreateWindow', [ :string, :int, :int, :int, :int, :uint32 ], :pointer
    attach_function :CreateRenderer, 'SDL_CreateRenderer', [:pointer, :int, :uint32], :pointer
    attach_function :CreateTexture, 'SDL_CreateTexture', [:pointer, :uint32, :int, :int, :int], :pointer
    attach_function :UpdateTexture, 'SDL_UpdateTexture', [:pointer, :pointer, :pointer, :int], :int
    attach_function :LockTexture, 'SDL_LockTexture', [:pointer, :pointer, :pointer, :int], :int
    attach_function :UnlockTexture, 'SDL_UnlockTexture', [:pointer], :void
    attach_function :RenderClear, 'SDL_RenderClear', [:pointer], :int
    attach_function :RenderCopy, 'SDL_RenderCopy', [:pointer, :pointer, :pointer, :pointer], :int
    attach_function :RenderPresent, 'SDL_RenderPresent', [:pointer], :int
    attach_function :PumpEvents, 'SDL_PumpEvents', [], :void
    attach_function :GetKeyboardState, 'SDL_GetKeyboardState', [:pointer], :pointer
    attach_function :SetHint, 'SDL_SetHint', [:string, :string], :int
    attach_function :RenderSetLogicalSize, 'SDL_RenderSetLogicalSize', [:pointer, :int, :int], :int
    attach_function :SetWindowTitle, 'SDL_SetWindowTitle', [:pointer, :string], :void
    attach_function :RaiseWindow, 'SDL_RaiseWindow', [:pointer], :void
    attach_function :GetError, 'SDL_GetError', [], :string
    attach_function :SetRenderDrawColor, 'SDL_SetRenderDrawColor', [:pointer, :uint8, :uint8, :uint8, :uint8], :int
    attach_function :PollEvent, 'SDL_PollEvent', [:pointer], :int

    QUIT = 0x100
  end
end
