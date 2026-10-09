# frozen_string_literal: true

require_relative '../../lib/rubyboy/emulator_wasm'
require_relative '../../lib/rubyboy/emulator_headless'
require_relative '../../lib/rubyboy/hardware_state'
require_relative '../../lib/executor'
require 'stringio'

RSpec.describe Rubyboy::EmulatorWasm do
  let(:rom_path) { File.expand_path('../../lib/roms/tobu.gb', __dir__) }
  let(:rom_data) { File.binread(rom_path).bytes }

  def state(emulator)
    %i[cpu timer ppu apu].map do |part|
      emulator.instance_variable_get("@#{part}").hardware_state
    end
  end

  def loop_rom
    data = rom_data.first(0x8000)
    data[0x100, 3] = [0xc3, 0, 1] # JP 0x0100: one instruction takes 16 cycles.
    data
  end

  it 'matches the desktop core, including APU state and copied audio blocks' do
    browser = described_class.new(rom_data)
    reference = Rubyboy::EmulatorHeadless.new(rom_path)
    reference_apu = reference.instance_variable_get(:@apu)
    original_apu_step = reference_apu.method(:step)
    samples = []
    reference_apu.define_singleton_method(:step) do |cycles|
      complete = original_apu_step.call(cycles)
      samples.concat(reference_apu.samples) if complete
      complete
    end
    browser_ppu = browser.instance_variable_get(:@ppu)
    original_ppu_step = browser_ppu.method(:step)
    frame_complete = false
    browser_ppu.define_singleton_method(:step) do |cycles|
      frame_complete = original_ppu_step.call(cycles)
    end
    produced_samples = 0

    120.times do
      samples = []
      reference.step
      browser_samples = []
      # A browser call can return early while Tobu disables the LCD. Compare
      # completed PPU frames and retain audio from those bounded calls as well.
      120.times do
        browser.step(15, 15)
        browser_samples.concat(browser.audio_samples)
        break if frame_complete
      end

      expect(frame_complete).to be(true)
      expect(browser.framebuffer).to eq(reference.instance_variable_get(:@ppu).buffer)
      expect(browser_samples).to eq(samples)
      expect(state(browser)).to eq(state(reference))
      produced_samples += samples.length
    end
    expect(produced_samples).to be > 0
  end

  it 'returns a framebuffer from step and keeps the partial APU block' do
    emulator = described_class.new(loop_rom)

    expect(emulator.step(15, 15)).to equal(emulator.framebuffer)
    first_audio = emulator.audio_samples.dup
    apu = emulator.instance_variable_get(:@apu)
    expect(first_audio.length).to eq(1024)
    expect(apu.instance_variable_get(:@sample_idx)).to be > 0

    emulator.step(15, 15)

    expect(emulator.audio_samples.length).to eq(2048)
    expect(first_audio.length).to eq(1024)
  end

  it 'returns after one frame of CPU time even when the LCD is disabled' do
    emulator = described_class.new(loop_rom)
    emulator.instance_variable_get(:@ppu).write_byte(0xff40, 0)
    cpu = emulator.instance_variable_get(:@cpu)
    instructions = 0
    allow(cpu).to receive(:exec).and_wrap_original do |method|
      instructions += 1
      method.call
    end

    expect(emulator.step(15, 15)).to equal(emulator.framebuffer)

    expect(instructions).to eq(70_224 / 16)
    expect(emulator.audio_samples.length).to eq(1024)
    expect(emulator.instance_variable_get(:@ppu).hardware_state[:registers][:ly]).to eq(0)
  end

  it 'uses active-low input masks' do
    emulator = described_class.new(loop_rom)

    emulator.step(14, 13)

    joypad = emulator.instance_variable_get(:@joypad).hardware_state
    expect(joypad[:direction_buttons]).to eq(0xfe)
    expect(joypad[:action_buttons]).to eq(0xfd)
  end
end

RSpec.describe Executor do
  let(:rom_path) { File.expand_path('../../lib/roms/tobu.gb', __dir__) }

  it 'writes little-endian pixels and stereo Float32 audio for a frame call' do
    executor = described_class.new(rom_path)
    writes = {}
    allow(File).to receive(:binwrite) { |path, bytes| writes[path] = bytes }

    executor.exec

    emulator = executor.instance_variable_get(:@emulator)
    expect(writes.fetch('/video.data').unpack('V*')).to eq(emulator.framebuffer)
    samples = writes.fetch('/audio.data').unpack('e*')
    expect(samples.length).to eq(emulator.audio_samples.length)
    samples.zip(emulator.audio_samples).each do |actual, expected|
      expect(actual).to be_within(1e-6).of(expected)
    end
  end

  it 'writes the framebuffer and skips empty audio' do
    executor = described_class.new(rom_path)
    emulator = executor.instance_variable_get(:@emulator)
    allow(emulator).to receive(:audio_samples).and_return([])
    allow(File).to receive(:binwrite)

    executor.exec

    expect(File).to have_received(:binwrite).with('/video.data', a_string_matching(/./m))
    expect(File).not_to have_received(:binwrite).with('/audio.data', anything)
  end

  it 'uses the existing packed ROM directory' do
    executor = described_class.new(rom_path)
    rom = File.binread(rom_path)
    allow(File).to receive(:open).with('/lib/roms/bgbtest.gb', 'r').and_yield(StringIO.new(rom))

    expect { executor.read_pre_installed_rom('bgbtest.gb') }.not_to raise_error
    expect { executor.read_pre_installed_rom('../other.gb') }.to raise_error('ROM not found in allowed ROMs')
  end
end
