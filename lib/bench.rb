# frozen_string_literal: true

require 'stackprof'
require_relative 'rubyboy'

module Rubyboy
  class Bench
    def stackprof
      StackProf.run(mode: :cpu, out: 'stackprof-cpu-myapp.dump', raw: true) do
        Rubyboy::Console.new('lib/roms/tobu.gb').bench
      end
    end

    def bench(count: 3, frames: 1500, path: 'lib/roms/tobu.gb')
      time_sum = 0
      count.times do |i|
        time = Rubyboy::Console.new(path).bench(frames)
        time_sum += time
        puts "#{i + 1}: #{time / 1_000_000_000.0} sec"
      end

      puts "FPS: #{frames * count * 1_000_000_000.0 / time_sum}"
    end
  end
end
