# frozen_string_literal: true

require_relative 'nombc'
require_relative 'mbc1'

module Rubyboy
  module Cartridge
    class Factory
      def self.create(rom, ram)
        case rom.cartridge_type
        when 0x00
          Nombc.new(rom)
        when 0x01..0x03
          Mbc1.new(rom, ram)
        when 0x08..0x09
          Nombc.new(rom)
        else
          raise "Unsupported cartridge type: #{cartridge_type}"
        end
      end
    end
  end
end
