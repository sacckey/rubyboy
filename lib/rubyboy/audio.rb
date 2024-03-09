# frozen_string_literal: true

require 'rubyboy/sdl'

module Rubyboy
  class Audio
    SAMPLE_RATE = 48000
    SAMPLES = 512

    def initialize
      SDL.InitSubSystem(SDL::INIT_AUDIO)

      desired = SDL::AudioSpec.new
      desired[:freq] = SAMPLE_RATE
      desired[:format] = SDL::AUDIO_F32SYS
      desired[:channels] = 2
      desired[:samples] = SAMPLES * 2

      @device = SDL.OpenAudioDevice(nil, 0, desired, nil, 0)

      SDL.PauseAudioDevice(@device, 0)
    end

    def queue(buffer)
      sleep(0.001) while SDL.GetQueuedAudioSize(@device) > 8192

      buf_ptr = FFI::MemoryPointer.new(:float, buffer.size)
      buf_ptr.put_array_of_float(0, buffer)

      SDL.QueueAudio(@device, buf_ptr, buffer.size * buf_ptr.type_size)
    end
  end
end
