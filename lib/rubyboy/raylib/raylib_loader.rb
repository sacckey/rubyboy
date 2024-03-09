# frozen_string_literal: true

require 'raylib'

module Rubyboy
  module Raylib
    class RaylibLoader
      include Raylib

      def load_raylib
        shared_lib_path = "#{Gem::Specification.find_by_name('raylib-bindings').full_gem_path}/lib/"
        case RUBY_PLATFORM
        when /mswin|msys|mingw/ # Windows
          Raylib.load_lib("#{shared_lib_path}libraylib.dll")
        when /darwin/ # macOS
          arch = RUBY_PLATFORM.split('-')[0]
          Raylib.load_lib(shared_lib_path + "libraylib.#{arch}.dylib")
        when /linux/ # Ubuntu Linux (x86_64 or aarch64)
          arch = RUBY_PLATFORM.split('-')[0]
          Raylib.load_lib(shared_lib_path + "libraylib.#{arch}.so")
        else
          raise "Unknown system: #{RUBY_PLATFORM}"
        end

        SetTraceLogLevel(LOG_ERROR)
      end

      def key_input_check
        direction = (IsKeyUp(KEY_D) && 1 || 0) | ((IsKeyUp(KEY_A) && 1 || 0) << 1) | ((IsKeyUp(KEY_W) && 1 || 0) << 2) | ((IsKeyUp(KEY_S) && 1 || 0) << 3)
        action = (IsKeyUp(KEY_K) && 1 || 0) | ((IsKeyUp(KEY_J) && 1 || 0) << 1) | ((IsKeyUp(KEY_U) && 1 || 0) << 2) | ((IsKeyUp(KEY_I) && 1 || 0) << 3)
        @joypad.direction_button(direction)
        @joypad.action_button(action)
      end
    end
  end
end
