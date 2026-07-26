# frozen_string_literal: true

require 'fileutils'
require 'tmpdir'

RSpec.describe Rubyboy::StateFile do
  let(:rom) { instance_double(Rubyboy::Rom, global_checksum_value: 0x1234) }
  let(:path) { File.join(Dir.tmpdir, "rubyboy-state-file-#{Process.pid}.state") }

  after do
    FileUtils.rm_f(path)
    FileUtils.rm_f("#{path}.tmp")
  end

  it 'writes a versioned state file and reads its payload' do
    payload = { console: { pc: 0x150 }, cartridge: { type: :mbc1 } }

    expect(described_class.write(path, rom:) { payload }).to be true

    loaded = nil
    expect(described_class.read(path, rom:) { |state| loaded = state }).to be true
    expect(loaded).to eq(payload)
  end

  it 'rejects files for a different ROM checksum' do
    described_class.write(path, rom:) { { ok: true } }
    other_rom = instance_double(Rubyboy::Rom, global_checksum_value: 0xabcd)

    expect(described_class.read(path, rom: other_rom) { raise 'should not load' }).to be false
  end

  it 'rejects unsupported format versions' do
    header = Rubyboy::StateFile::MAGIC.b + [99, rom.global_checksum_value, 0].pack('L<S<S<')
    File.binwrite(path, header + Marshal.dump({ ok: true }))

    expect(described_class.read(path, rom:) { raise 'should not load' }).to be false
  end

  it 'rejects files without the state magic' do
    File.binwrite(path, 'not a rubyboy state')

    expect(described_class.read(path, rom:) { raise 'should not load' }).to be false
  end
end
