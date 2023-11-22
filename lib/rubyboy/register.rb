# frozen_string_literal: true

module Rubyboy
  class Register
    attr_reader :value

    def initialize(name:, value:)
      @name = name
      @value = value
    end

    def value=(v)
      @value = v & 0xff
    end

    def increment
      @value = (@value + 1) & 0xff
    end

    def decrement
      @value = (@value - 1) & 0xff
    end
  end
end
