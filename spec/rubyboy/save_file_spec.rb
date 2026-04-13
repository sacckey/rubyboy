# frozen_string_literal: true

require 'tmpdir'

RSpec.describe Rubyboy::SaveFile do
  around do |example|
    Dir.mktmpdir('rubyboy-savefile-spec') do |dir|
      @tmpdir = dir
      example.run
    end
  end

  let(:path) { File.join(@tmpdir, 'pokemon.sav') }
  let(:save_file) { described_class.new(path) }

  describe '#read' do
    it 'returns nil when the save file does not exist' do
      expect(save_file.read(8 * 1024)).to be_nil
    end

    it 'returns the byte array when the size matches' do
      File.binwrite(path, [0xaa, 0xbb, 0xcc, 0xdd].pack('C*'))
      expect(save_file.read(4)).to eq([0xaa, 0xbb, 0xcc, 0xdd])
    end

    it 'returns nil and warns when the size does not match' do
      File.binwrite(path, [0x01, 0x02].pack('C*'))
      expect { expect(save_file.read(4)).to be_nil }.to output(/size mismatch/).to_stderr
    end

    it 'returns nil and warns when the file cannot be read' do
      File.binwrite(path, 'data')
      File.chmod(0o000, path)
      expect { expect(save_file.read(4)).to be_nil }.to output(/failed to read/).to_stderr
    ensure
      File.chmod(0o600, path) if File.exist?(path)
    end
  end

  describe '#write' do
    it 'writes the bytes atomically via a tmp + rename' do
      expect(save_file.write([0x10, 0x20, 0x30])).to be true
      expect(File.binread(path).bytes).to eq([0x10, 0x20, 0x30])
      expect(File.exist?("#{path}.tmp")).to be false
    end

    it 'overwrites an existing save file in place' do
      File.binwrite(path, [0xff, 0xff].pack('C*'))
      save_file.write([0x01, 0x02])
      expect(File.binread(path).bytes).to eq([0x01, 0x02])
    end

    it 'returns false and warns when the directory is not writable' do
      File.chmod(0o500, @tmpdir)
      expect { expect(save_file.write([0x00])).to be false }.to output(/failed to write/).to_stderr
    ensure
      File.chmod(0o700, @tmpdir)
    end
  end
end
