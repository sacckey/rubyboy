# frozen_string_literal: true

RSpec.describe Rubyboy::Rom do
  # Build a minimal valid ROM header with configurable cartridge_type / ram_size bytes.
  def build_rom(cartridge_type: 0x00, ram_size: 0x00)
    data = Array.new(0x200, 0)
    Rubyboy::Rom::LOGO_DUMP.each_with_index { |b, i| data[0x104 + i] = b }
    data[0x147] = cartridge_type
    data[0x149] = ram_size
    described_class.new(data)
  end

  describe '#ram_size_bytes' do
    {
      0x00 => 0,
      0x01 => 2 * 1024,
      0x02 => 8 * 1024,
      0x03 => 32 * 1024,
      0x04 => 128 * 1024,
      0x05 => 64 * 1024
    }.each do |header_value, expected_bytes|
      it "returns #{expected_bytes} bytes for header value 0x#{format('%02x', header_value)}" do
        expect(build_rom(ram_size: header_value).ram_size_bytes).to eq(expected_bytes)
      end
    end

    it 'returns 0 for unknown header values' do
      expect(build_rom(ram_size: 0x7f).ram_size_bytes).to eq(0)
    end
  end

  describe '#battery?' do
    [0x03, 0x06, 0x09, 0x0d, 0x0f, 0x10, 0x13, 0x1b, 0x1e, 0x22, 0xff].each do |type|
      it "returns true for cartridge type 0x#{format('%02x', type)}" do
        expect(build_rom(cartridge_type: type).battery?).to be true
      end
    end

    [0x00, 0x01, 0x02, 0x05, 0x08, 0x11, 0x12, 0x19, 0x1a].each do |type|
      it "returns false for cartridge type 0x#{format('%02x', type)}" do
        expect(build_rom(cartridge_type: type).battery?).to be false
      end
    end
  end
end
