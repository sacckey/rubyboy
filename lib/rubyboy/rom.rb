# frozen_string_literal: true

module Rubyboy
  class Rom
    attr_reader :data, :entroy_point, :logo, :title, :new_licensee_code, :sgb_flag, :cartridge_type, :rom_size, :ram_size, :destination_code, :old_licensee_code, :mask_rom_version_number, :header_checksum, :global_checksum

    LOGO_DUMP = %w[
      CE ED 66 66 CC 0D 00 0B 03 73 00 83 00 0C 00 0D
      00 08 11 1F 88 89 00 0E DC CC 6E E6 DD DD D9 99
      BB BB 67 63 6E 0E EC CC DD DC 99 9F BB B9 33 3E
    ].map(&:hex).freeze

    RAM_SIZE_BYTES = {
      0x00 => 0,
      0x01 => 2 * 1024,
      0x02 => 8 * 1024,
      0x03 => 32 * 1024,
      0x04 => 128 * 1024,
      0x05 => 64 * 1024
    }.freeze

    BATTERY_CARTRIDGE_TYPES = [0x03, 0x06, 0x09, 0x0d, 0x0f, 0x10, 0x13, 0x1b, 0x1e, 0x22, 0xff].freeze

    def initialize(data)
      @data = data
      load_data
    end

    def ram_size_bytes
      RAM_SIZE_BYTES.fetch(@ram_size, 0)
    end

    def battery?
      BATTERY_CARTRIDGE_TYPES.include?(@cartridge_type)
    end

    private

    def load_data
      @entroy_point = @data[0x100..0x103]
      @logo = @data[0x104..0x133]
      raise 'logo is not match' unless @logo == LOGO_DUMP

      @title = @data[0x134..0x143]
      @new_licensee_code = @data[0x144..0x145]
      @sgb_flag = @data[0x146]
      @cartridge_type = @data[0x147]
      @rom_size = @data[0x148]
      @ram_size = @data[0x149]
      @destination_code = @data[0x14A]
      @old_licensee_code = @data[0x14B]
      @mask_rom_version_number = @data[0x14C]
      @header_checksum = @data[0x14D]
      @global_checksum = @data[0x14E..0x14F]
    end
  end
end
