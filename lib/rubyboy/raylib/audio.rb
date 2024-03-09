# frozen_string_literal: true

require 'raylib'

module Rubyboy
  module Raylib
    class Audio
      include Raylib

      MAX_SAMPLES = 512

      def initialize
        InitAudioDevice()
        SetAudioStreamBufferSizeDefault(MAX_SAMPLES * 2)
        @stream = LoadAudioStream(48000, 32, 2)
        PlayAudioStream(@stream)
      end

      def play(samples)
        samples_pointer = FFI::MemoryPointer.new(:float, samples.size)
        samples_pointer.put_array_of_float(0, samples)

        UpdateAudioStream(@stream, samples_pointer, samples.size)
      end

      def close
        UnloadAudioStream(@stream)
        CloseAudioDevice()
      end
    end
  end
end
