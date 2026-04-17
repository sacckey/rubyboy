# frozen_string_literal: true

RSpec.describe Rubyboy::Cartridge::Mbc1 do
  # Minimal rom/ram doubles — only the fields Mbc1 actually touches.
  let(:rom_data) { Array.new(0x8000, 0) }
  let(:rom) { instance_double(Rubyboy::Rom, data: rom_data) }
  let(:eram_size) { 8 * 1024 }
  let(:ram) do
    ram = instance_double(Rubyboy::Ram)
    storage = Array.new(eram_size, 0)
    allow(ram).to receive(:eram).and_return(storage)
    ram
  end
  let(:mbc) { described_class.new(rom, ram) }

  describe 'ROM address windows' do
    let(:rom_data) { Array.new(128 * 0x4000) { |i| i / 0x4000 } }

    it 'maps the lower window to bank 0 in default ROM banking mode' do
      mbc.write_byte(0x4000, 0x02)
      expect(mbc.read_byte(0x0000)).to eq(0)
    end

    it 'maps the upper window using high bits and the selected low bank' do
      mbc.write_byte(0x2000, 0x03)
      mbc.write_byte(0x4000, 0x02)
      expect(mbc.read_byte(0x4000)).to eq(0x43)
    end

    it 'maps low bank 0 to bank 1 within the selected high-bit group' do
      mbc.write_byte(0x2000, 0x00)
      mbc.write_byte(0x4000, 0x01)
      expect(mbc.read_byte(0x4000)).to eq(0x21)
    end

    it 'maps the lower window using high bits in RAM banking mode' do
      mbc.write_byte(0x4000, 0x02)
      mbc.write_byte(0x6000, 0x01)
      expect(mbc.read_byte(0x0000)).to eq(0x40)
    end

    it 'keeps high bits active for the upper window in RAM banking mode' do
      mbc.write_byte(0x2000, 0x04)
      mbc.write_byte(0x4000, 0x03)
      mbc.write_byte(0x6000, 0x01)
      expect(mbc.read_byte(0x4000)).to eq(0x64)
    end
  end

  describe 'RAM enable gate' do
    it 'reads 0xff from SRAM while RAM is disabled' do
      expect(mbc.read_byte(0xa000)).to eq(0xff)
    end

    it 'ignores writes while RAM is disabled' do
      mbc.write_byte(0xa000, 0x42)
      expect(ram.eram[0]).to eq(0)
    end

    it 'enables RAM when 0x0A is written to 0x0000..0x1fff' do
      mbc.write_byte(0x0000, 0x0a)
      mbc.write_byte(0xa000, 0x42)
      expect(mbc.read_byte(0xa000)).to eq(0x42)
    end

    it 'disables RAM when a non-0xA value is written' do
      mbc.write_byte(0x0000, 0x0a)
      mbc.write_byte(0xa000, 0x42)
      mbc.write_byte(0x0000, 0x00)
      expect(mbc.read_byte(0xa000)).to eq(0xff)
    end
  end

  describe 'single-bank RAM (8 KB)' do
    before { mbc.write_byte(0x0000, 0x0a) }

    it 'stores a byte at the expected offset' do
      mbc.write_byte(0xa000, 0x12)
      mbc.write_byte(0xbfff, 0x34)
      expect(ram.eram[0x0000]).to eq(0x12)
      expect(ram.eram[0x1fff]).to eq(0x34)
    end

    it 'reads back stored bytes' do
      mbc.write_byte(0xabcd, 0x99)
      expect(mbc.read_byte(0xabcd)).to eq(0x99)
    end
  end

  describe 'banked RAM (32 KB, ram_banking_mode)' do
    let(:eram_size) { 32 * 1024 }

    before do
      mbc.write_byte(0x0000, 0x0a)   # enable RAM
      mbc.write_byte(0x6000, 0x01)   # select RAM banking mode
    end

    it 'stores bank 0 at offset 0x0000..0x1fff' do
      mbc.write_byte(0x4000, 0x00)   # ram_bank = 0
      mbc.write_byte(0xa000, 0xaa)
      expect(ram.eram[0x0000]).to eq(0xaa)
    end

    it 'stores bank 1 at offset 0x2000..0x3fff' do
      mbc.write_byte(0x4000, 0x01)
      mbc.write_byte(0xa000, 0xbb)
      expect(ram.eram[0x2000]).to eq(0xbb)
    end

    it 'stores bank 2 at offset 0x4000..0x5fff' do
      mbc.write_byte(0x4000, 0x02)
      mbc.write_byte(0xa000, 0xcc)
      expect(ram.eram[0x4000]).to eq(0xcc)
    end

    it 'stores bank 3 at offset 0x6000..0x7fff' do
      mbc.write_byte(0x4000, 0x03)
      mbc.write_byte(0xa000, 0xdd)
      expect(ram.eram[0x6000]).to eq(0xdd)
    end

    it 'keeps different banks isolated' do
      mbc.write_byte(0x4000, 0x00)
      mbc.write_byte(0xa000, 0x11)
      mbc.write_byte(0x4000, 0x02)
      mbc.write_byte(0xa000, 0x22)

      mbc.write_byte(0x4000, 0x00)
      expect(mbc.read_byte(0xa000)).to eq(0x11)
      mbc.write_byte(0x4000, 0x02)
      expect(mbc.read_byte(0xa000)).to eq(0x22)
    end
  end

  describe 'undersized cartridge RAM' do
    let(:eram_size) { 2 * 1024 }

    it 'drops writes that fall outside the actual eram' do
      mbc.write_byte(0x0000, 0x0a)
      expect { mbc.write_byte(0xb000, 0x55) }.not_to raise_error
      expect(ram.eram.compact.length).to eq(ram.eram.length) # no holes
    end
  end
end
