# frozen_string_literal: true

module Rubyboy
  module Mbc
    class Nombc
      def initialize(rom)
        @rom = rom
      end

      def read_byte(addr)
        @rom.data[addr]
      end

      def write_byte(_addr, _value)
        # do nothing
      end
    end
  end
end
