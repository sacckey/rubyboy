# frozen_string_literal: true

module Rubyboy
  module Cartridge
    class Nombc
      def initialize(rom)
        @rom = rom
      end

      def read_byte(addr)
        case addr
        when 0x0000..0x7fff
          @rom.data[addr]
        else
          raise "not implemented: read_byte #{addr}"
        end
      end

      def write_byte(_addr, _value)
        # do nothing
      end
    end
  end
end
