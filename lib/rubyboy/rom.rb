# frozen_string_literal: true

module Rubyboy
  class Rom
    attr_accessor :data, :entroy_point, :logo, :title, :new_licensee_code, :sgb_flag, :cartridge_type, :rom_size, :ram_size, :destination_code, :old_licensee_code, :mask_rom_version_number, :header_checksum, :global_checksum

    LOGO_DUMP = %w[
      CE ED 66 66 CC 0D 00 0B 03 73 00 83 00 0C 00 0D
      00 08 11 1F 88 89 00 0E DC CC 6E E6 DD DD D9 99
      BB BB 67 63 6E 0E EC CC DD DC 99 9F BB B9 33 3E
    ].map(&:hex).freeze

    def initialize(data)
      @data = data
      load_data
    end

    private

    def load_data
      # The Cartridge Header
      # see: https://gbdev.io/pandocs/The_Cartridge_Header.html

      # 0x100 - 0x103: Entry Point
      @entroy_point = @data[0x100..0x103]
      # p data[0x102..0x103].pack('C*').unpack('v').first

      # 0x104 - 0x133: Nintendo Logo
      @logo = @data[0x104..0x133]
      raise 'logo is not match' unless @logo == LOGO_DUMP

      # 0x134 - 0x143: Title
      @title = @data[0x134..0x143]
      # p data[0x134..0x143].pack('C*').strip

      # 0x144 - 0x145: New Licensee Code
      @new_licensee_code = @data[0x144..0x145]

      # 0x146: SGB Flag
      @sgb_flag = @data[0x146]

      # 0x147: Cartridge Type
      @cartridge_type = @data[0x147]

      # 0x148: ROM Size
      @rom_size = @data[0x148]

      # 0x149: RAM Size
      @ram_size = @data[0x149]

      # 0x14A: Destination Code
      @destination_code = @data[0x14A]

      # 0x14B: Old Licensee Code
      @old_licensee_code = @data[0x14B]

      # 0x14C: Mask ROM Version number
      @mask_rom_version_number = @data[0x14C]

      # 0x14D: Header Checksum
      @header_checksum = @data[0x14D]

      # 0x14E - 0x14F: Global Checksum
      @global_checksum = @data[0x14E..0x14F]
    end
  end
end
