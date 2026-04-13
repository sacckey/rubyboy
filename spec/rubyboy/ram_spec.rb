# frozen_string_literal: true

RSpec.describe Rubyboy::Ram do
  def rom_with_ram_size(byte)
    instance_double(Rubyboy::Rom, ram_size_bytes: Rubyboy::Rom::RAM_SIZE_BYTES.fetch(byte))
  end

  it 'sizes eram to 0 bytes when the header declares no RAM (0x00)' do
    ram = described_class.new(rom_with_ram_size(0x00))
    expect(ram.eram.size).to eq(0)
  end

  it 'sizes eram to 8 KB for header 0x02' do
    ram = described_class.new(rom_with_ram_size(0x02))
    expect(ram.eram.size).to eq(8 * 1024)
  end

  it 'sizes eram to 32 KB for header 0x03' do
    ram = described_class.new(rom_with_ram_size(0x03))
    expect(ram.eram.size).to eq(32 * 1024)
  end

  it 'always allocates the fixed work / high RAM regions' do
    ram = described_class.new(rom_with_ram_size(0x00))
    expect(ram.wram1.size).to eq(0x1000)
    expect(ram.wram2.size).to eq(0x1000)
    expect(ram.hram.size).to eq(0x80)
  end
end
