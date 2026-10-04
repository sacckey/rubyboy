# frozen_string_literal: true

require 'json'
require_relative 'rubyboy/emulator_headless'

module Rubyboy
  class Bench
    class WindowClosed < StandardError; end

    def run(count: 3, frames: 1500, rom_path: 'lib/roms/tobu.gb', warmup_frames: 0, render: false, json: false)
      validate_integer(:count, count, 1)
      validate_integer(:frames, frames, 1)
      validate_integer(:warmup_frames, warmup_frames, 0)
      require_relative 'rubyboy/lcd' if render

      trials = []
      time_sum = 0
      count.times do |i|
        time = run_trial(rom_path, frames, warmup_frames, render)
        elapsed_seconds = time / 1_000_000_000.0
        trials << { trial: i + 1, frames:, elapsed_seconds:, fps: frames / elapsed_seconds }
        puts "#{i + 1}: #{elapsed_seconds} sec" unless json
        time_sum += time
      end

      result = {
        schema_version: 1,
        rom_path: File.expand_path(rom_path),
        count:,
        frames:,
        warmup_frames:,
        render:,
        runtime:,
        conditions: { apu: true, audio_output: false, realtime_sync: false, vsync: render ? false : nil, input: false, save: false },
        trials:,
        total_frames: frames * count,
        elapsed_seconds: time_sum / 1_000_000_000.0,
        fps: frames * count * 1_000_000_000.0 / time_sum
      }
      puts(json ? JSON.generate(result) : "FPS: #{result[:fps]}")
      result
    end

    private

    def validate_integer(name, value, minimum)
      return if value.is_a?(Integer) && value >= minimum

      requirement = minimum == 0 ? 'a nonnegative integer' : 'a positive integer'
      raise ArgumentError, "#{name} must be #{requirement}"
    end

    def run_trial(rom_path, frames, warmup_frames, render)
      emulator = Rubyboy::EmulatorHeadless.new(rom_path)
      lcd = Rubyboy::Lcd.new(vsync: false) if render
      begin
        run_frames(emulator, lcd, warmup_frames)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        run_frames(emulator, lcd, frames)
        Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start_time
      ensure
        lcd&.close_window
      end
    end

    def run_frames(emulator, lcd, frames)
      frame_count = 0
      while frame_count < frames
        raise WindowClosed, 'Benchmark stopped because the window was closed.' if lcd&.window_should_close?

        emulator.step
        lcd&.draw(emulator.framebuffer)
        frame_count += 1
      end
    end

    def runtime
      yjit_enabled = defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false
      { engine: RUBY_ENGINE, version: RUBY_VERSION, description: RUBY_DESCRIPTION, platform: RUBY_PLATFORM, yjit_enabled: }
    end
  end
end
