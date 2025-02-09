# frozen_string_literal: true

require 'stackprof'
require_relative 'rubyboy/emulator'

module Rubyboy
  class Stackprof
    def run
      StackProf.run(mode: :cpu, out: 'stackprof-cpu-myapp.dump', raw: true) do
        Rubyboy::Emulator.new('lib/roms/tobu.gb').bench
      end
    end
  end
end
