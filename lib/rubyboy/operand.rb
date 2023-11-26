# frozen_string_literal: true

module Rubyboy
  class Operand
    attr_reader :type, :value

    def initialize(type:, value:)
      @type = type
      @value = value
    end
  end
end
