# frozen_string_literal: true

module Rubyboy
  class Operand
    attr_reader :type, :value

    def initialize(type:, value: 0)
      @type = type
      @value = value
    end
  end
end
