# frozen_string_literal: true

require 'bench'
require 'open3'
require 'rbconfig'

RSpec.describe Rubyboy::Bench do
  let(:emulator) { instance_double(Rubyboy::EmulatorHeadless, step: nil) }

  before do
    allow(Rubyboy::EmulatorHeadless).to receive(:new).and_return(emulator)
  end

  it 'starts each trial from a fresh emulator, warms up identically, and aggregates measured durations' do
    second_emulator = instance_double(Rubyboy::EmulatorHeadless, step: nil)
    allow(Rubyboy::EmulatorHeadless).to receive(:new).with('test.gb').and_return(emulator, second_emulator)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(1_000_000_000, 2_000_000_000, 3_000_000_000, 5_000_000_000)

    expect do
      described_class.new.run(count: 2, frames: 3, warmup_frames: 2, rom_path: 'test.gb')
    end.to output("1: 1.0 sec\n2: 2.0 sec\nFPS: 2.0\n").to_stdout

    expect(Rubyboy::EmulatorHeadless).to have_received(:new).with('test.gb').twice
    expect(emulator).to have_received(:step).exactly(5).times
    expect(second_emulator).to have_received(:step).exactly(5).times
  end

  %i[count frames].each do |option|
    [0, -1, 1.5, '1', nil].each do |value|
      it "rejects #{option}=#{value.inspect} before initializing an emulator" do
        expect(Rubyboy::EmulatorHeadless).not_to receive(:new)

        expect do
          described_class.new.run(**{ option => value })
        end.to raise_error(ArgumentError, "#{option} must be a positive integer")
      end
    end
  end

  [-1, 1.5, '1', nil].each do |value|
    it "rejects warmup_frames=#{value.inspect} before initializing an emulator" do
      expect(Rubyboy::EmulatorHeadless).not_to receive(:new)

      expect do
        described_class.new.run(warmup_frames: value)
      end.to raise_error(ArgumentError, 'warmup_frames must be a nonnegative integer')
    end
  end
end

RSpec.describe 'rubyboy-bench executable' do
  let(:repository_root) { File.expand_path('..', __dir__) }

  it 'runs the requested measured and warmup frames' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--count', '1', '--frames', '1', '--warmup-frames', '1', chdir: repository_root)

    expect(status.success?).to be(true), stderr
    expect(stdout).to match(/^1: .* sec$/)
    expect(stdout).to match(/^FPS: /)
  end

  it 'rejects an invalid count with a failing exit status' do
    _stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--count', '0', chdir: repository_root)

    expect(status.exitstatus).to eq(1)
    expect(stderr).to include('count must be a positive integer')
  end

  %w[--count --frames --warmup-frames].each do |option|
    %w[abc 1.5].each do |value|
      it "rejects malformed #{option} #{value} without a stack trace" do
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', option, value, chdir: repository_root)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq('')
        expect(stderr).to include('invalid')
        expect(stderr).not_to include('from ')
      end
    end
  end

  it 'rejects a negative warmup count instead of starting a trial' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--warmup-frames', '-1', chdir: repository_root)

    expect(status.exitstatus).to eq(1)
    expect(stdout).not_to include('FPS')
    expect(stderr).to include('warmup_frames must be a nonnegative integer')
  end
end
