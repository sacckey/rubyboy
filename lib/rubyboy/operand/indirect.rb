# frozen_string_literal: true

module Rubyboy
  module Operand
    class Indirect
      attr_reader :value

      def initialize(value)
        @value = value
      end
    end
  end
end
