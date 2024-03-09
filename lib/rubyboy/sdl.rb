# frozen_string_literal: true

require 'ffi'

module Rubyboy
  module SDL
    extend FFI::Library
    ffi_lib 'SDL2'

    INIT_TIMER = 0x01
    INIT_AUDIO = 0x10
    INIT_VIDEO = 0x20
    INIT_KEYBOARD = 0x200
    WINDOW_RESIZABLE = 0x20
    PIXELFORMAT_RGB24 = 386930691
    SDL_WINDOW_RESIZABLE = 0x20
    QUIT = 0x100

    SDL_SCANCODE_W = 26
    SDL_SCANCODE_A = 4
    SDL_SCANCODE_S = 22
    SDL_SCANCODE_D = 7
    SDL_SCANCODE_J = 13
    SDL_SCANCODE_K = 14
    SDL_SCANCODE_U = 24
    SDL_SCANCODE_I = 12

    attach_function :Init, 'SDL_Init', [:uint32], :int
    attach_function :InitSubSystem, 'SDL_InitSubSystem', [:uint32], :int
    attach_function :CreateWindow, 'SDL_CreateWindow', %i[string int int int int uint32], :pointer
    attach_function :DestroyWindow, 'SDL_DestroyWindow', [:pointer], :void
    attach_function :CreateRenderer, 'SDL_CreateRenderer', %i[pointer int uint32], :pointer
    attach_function :CreateTexture, 'SDL_CreateTexture', %i[pointer uint32 int int int], :pointer
    attach_function :UpdateTexture, 'SDL_UpdateTexture', %i[pointer pointer pointer int], :int
    attach_function :LockTexture, 'SDL_LockTexture', %i[pointer pointer pointer int], :int
    attach_function :UnlockTexture, 'SDL_UnlockTexture', [:pointer], :void
    attach_function :RenderClear, 'SDL_RenderClear', [:pointer], :int
    attach_function :RenderCopy, 'SDL_RenderCopy', %i[pointer pointer pointer pointer], :int
    attach_function :RenderPresent, 'SDL_RenderPresent', [:pointer], :int
    attach_function :PumpEvents, 'SDL_PumpEvents', [], :void
    attach_function :GetKeyboardState, 'SDL_GetKeyboardState', [:pointer], :pointer
    attach_function :SetHint, 'SDL_SetHint', %i[string string], :int
    attach_function :RenderSetLogicalSize, 'SDL_RenderSetLogicalSize', %i[pointer int int], :int
    attach_function :SetWindowTitle, 'SDL_SetWindowTitle', %i[pointer string], :void
    attach_function :RaiseWindow, 'SDL_RaiseWindow', [:pointer], :void
    attach_function :GetError, 'SDL_GetError', [], :string
    attach_function :SetRenderDrawColor, 'SDL_SetRenderDrawColor', %i[pointer uint8 uint8 uint8 uint8], :int
    attach_function :PollEvent, 'SDL_PollEvent', [:pointer], :int
    attach_function :Quit, 'SDL_Quit', [], :void

    AUDIO_F32SYS = 0x8120
    attach_function :OpenAudioDevice, 'SDL_OpenAudioDevice', %i[string int pointer pointer int], :uint32
    attach_function :PauseAudioDevice, 'SDL_PauseAudioDevice', %i[uint32 int], :void
    attach_function :GetQueuedAudioSize, 'SDL_GetQueuedAudioSize', [:uint32], :uint32
    attach_function :QueueAudio, 'SDL_QueueAudio', %i[uint32 pointer uint32], :int

    class AudioSpec < FFI::Struct
      layout(
        :freq, :int,
        :format, :ushort,
        :channels, :uchar,
        :silence, :uchar,
        :samples, :ushort,
        :padding, :ushort,
        :size, :uint,
        :callback, :pointer,
        :userdata, :pointer
      )
    end
  end
end
