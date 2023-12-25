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

    def bench
      bench_cnt = 3
      time_sum = 0
      bench_cnt.times do |i|
        time = Rubyboy::Console.new('lib/roms/tobu.gb').bench
        time_sum += time
        puts "#{i + 1}: #{time} sec"
      end

      puts "FPS: #{1500 * bench_cnt / time_sum}"
    end
  end
end
