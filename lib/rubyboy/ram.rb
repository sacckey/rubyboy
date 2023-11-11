# frozen_string_literal: true

module Rubyboy
  class Ram
    attr_accessor :eram, :wram1, :wram2

    def initialize
      @eram = Array.new(0x2000, 0)
      @wram1 = Array.new(0x1000, 0)
      @wram2 = Array.new(0x1000, 0)
    end
  end
end
