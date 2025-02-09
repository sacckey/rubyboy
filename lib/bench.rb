# frozen_string_literal: true

require_relative 'rubyboy/emulator_headless'

module Rubyboy
  class Bench
    def run(count: 3, frames: 1500, rom_path: 'lib/roms/tobu.gb')
      time_sum = 0

      count.times do |i|
        emulator = Rubyboy::EmulatorHeadless.new(rom_path)
        frame_count = 0
        start_time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond)
        while frame_count < frames
          emulator.step
          frame_count += 1
        end
        time = Process.clock_gettime(Process::CLOCK_MONOTONIC, :nanosecond) - start_time
        puts "#{i + 1}: #{time / 1_000_000_000.0} sec"

        time_sum += time
      end

      puts "FPS: #{frames * count * 1_000_000_000.0 / time_sum}"
    end
  end
end
