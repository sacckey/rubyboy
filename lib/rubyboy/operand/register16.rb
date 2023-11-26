# frozen_string_literal: true

module Rubyboy
  module Operand
    class Register16
      attr_reader :value

      def initialize(value)
        @value = value
      end
    end
  end
end
