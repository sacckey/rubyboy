# frozen_string_literal: true

require_relative 'rubyboy/emulator_headless'

module Rubyboy
  class Bench
    def run(count: 3, frames: 1500, rom_path: Rom::DEFAULT_PATH, warmup_frames: 0)
      validate_integer(:count, count, 1)
      validate_integer(:frames, frames, 1)
      validate_integer(:warmup_frames, warmup_frames, 0)

      time_sum = 0
      count.times do |i|
        emulator = Rubyboy::EmulatorHeadless.new(rom_path)
        run_frames(emulator, warmup_frames)
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        run_frames(emulator, frames)
        time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start_time
        puts "#{i + 1}: #{time / 1_000_000_000.0} sec"

        time_sum += time
      end

      puts "FPS: #{frames * count * 1_000_000_000.0 / time_sum}"
    end

    private

    def validate_integer(name, value, minimum)
      return if value.is_a?(Integer) && value >= minimum

      requirement = minimum == 0 ? 'a nonnegative integer' : 'a positive integer'
      raise ArgumentError, "#{name} must be #{requirement}"
    end

    def run_frames(emulator, frames)
      frame_count = 0
      while frame_count < frames
        emulator.step
        frame_count += 1
      end
    end
  end
end
