# frozen_string_literal: true

require 'bench'
require 'json'
require 'open3'
require 'rbconfig'

RSpec.describe Rubyboy::Bench do
  let(:framebuffer) { [0x12345678] }
  let(:emulator) { instance_double(Rubyboy::EmulatorHeadless, step: nil, framebuffer:) }
  let(:lcd) { instance_double(Rubyboy::Lcd, draw: nil, window_should_close?: false, close_window: nil) }

  before do
    allow(Rubyboy::EmulatorHeadless).to receive(:new).and_return(emulator)
    allow(Rubyboy::Lcd).to receive(:new).and_return(lcd)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(1_000_000_000, 2_000_000_000)
  end

  it 'starts each trial from a fresh emulator, warms up identically, and aggregates measured durations' do
    second_emulator = instance_double(Rubyboy::EmulatorHeadless, step: nil)
    allow(Rubyboy::EmulatorHeadless).to receive(:new).with('test.gb').and_return(emulator, second_emulator)
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(1_000_000_000, 2_000_000_000, 3_000_000_000, 5_000_000_000)
    result = nil

    expect do
      result = described_class.new.run(count: 2, frames: 3, warmup_frames: 2, rom_path: 'test.gb')
    end.to output("1: 1.0 sec\n2: 2.0 sec\nFPS: 2.0\n").to_stdout

    expect(Rubyboy::EmulatorHeadless).to have_received(:new).with('test.gb').twice
    expect(emulator).to have_received(:step).exactly(5).times
    expect(second_emulator).to have_received(:step).exactly(5).times
    expect(result[:trials]).to eq([
                                    { trial: 1, frames: 3, elapsed_seconds: 1.0, fps: 3.0 },
                                    { trial: 2, frames: 3, elapsed_seconds: 2.0, fps: 1.5 }
                                  ])
    expect(result[:total_frames]).to eq(6)
    expect(result[:elapsed_seconds]).to eq(3.0)
    expect(result[:fps]).to eq(2.0)
  end

  it 'keeps headless trials free of display and audio device output' do
    expect(Rubyboy::Lcd).not_to receive(:new)
    expect(Rubyboy::Audio).not_to receive(:new)

    expect { described_class.new.run(count: 1, frames: 2) }.to output("1: 1.0 sec\nFPS: 2.0\n").to_stdout

    expect(emulator).to have_received(:step).twice
  end

  it 'draws warmup and measured frames from the same headless core and excludes setup and cleanup from timing' do
    events = []
    allow(Rubyboy::EmulatorHeadless).to receive(:new) {
                                          events << :initialize
                                          emulator
                                        }
    allow(Rubyboy::Lcd).to receive(:new) {
                             events << :open
                             lcd
                           }
    allow(emulator).to receive(:step) { events << :step }
    allow(lcd).to receive(:draw).with(framebuffer) { events << :draw }
    allow(lcd).to receive(:window_should_close?) {
                    events << :poll
                    false
                  }
    allow(lcd).to receive(:close_window) { events << :close }
    times = [1_000_000_000, 2_000_000_000]
    allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond) do
      events << :clock
      times.shift
    end

    expect { described_class.new.run(count: 1, frames: 2, warmup_frames: 1, render: true) }.to output("1: 1.0 sec\nFPS: 2.0\n").to_stdout

    expect(events).to eq(%i[initialize open poll step draw clock poll step draw poll step draw clock close])
    expect(Rubyboy::Lcd).to have_received(:new).with(vsync: false).once
    expect(lcd).to have_received(:draw).with(framebuffer).exactly(3).times
    expect(lcd).to have_received(:close_window).once
  end

  it 'closes the display and aborts without a completed-trial result when the window closes early' do
    allow(lcd).to receive(:window_should_close?).and_return(false, true)
    expect($stdout).not_to receive(:puts)

    expect do
      described_class.new.run(count: 1, frames: 3, render: true)
    end.to raise_error(Rubyboy::Bench::WindowClosed, 'Benchmark stopped because the window was closed.')

    expect(emulator).to have_received(:step).once
    expect(lcd).to have_received(:close_window).once
  end

  it 'also aborts and cleans up when the window closes during warmup' do
    allow(lcd).to receive(:window_should_close?).and_return(true)
    expect(Process).not_to receive(:clock_gettime)

    expect do
      described_class.new.run(count: 1, frames: 3, warmup_frames: 1, render: true)
    end.to raise_error(Rubyboy::Bench::WindowClosed)

    expect(emulator).not_to have_received(:step)
    expect(lcd).to have_received(:close_window).once
  end

  it 'closes the display when emulation raises an error' do
    allow(emulator).to receive(:step).and_raise('emulation failed')

    expect do
      described_class.new.run(count: 1, frames: 1, render: true)
    end.to raise_error(RuntimeError, 'emulation failed')

    expect(lcd).to have_received(:close_window).once
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

  it 'outputs one JSON document with conditions, actual runtime identity, and individual trial results' do
    output = StringIO.new
    allow($stdout).to receive(:puts) { |text| output.puts(text) }

    result = described_class.new.run(count: 1, frames: 2, warmup_frames: 1, rom_path: 'test.gb', json: true)
    document = JSON.parse(output.string)

    expect(document).to eq(JSON.parse(JSON.generate(result)))
    expect(document['rom_path']).to eq(File.expand_path('test.gb'))
    expect(document['warmup_frames']).to eq(1)
    expect(document['conditions']).to eq('apu' => true, 'audio_output' => false, 'realtime_sync' => false, 'vsync' => nil, 'input' => false, 'save' => false)
    expect(document['runtime']['description']).to eq(RUBY_DESCRIPTION)
    expect(document['runtime']['engine']).to eq(RUBY_ENGINE)
    expect(document['runtime']['yjit_enabled']).to eq(defined?(RubyVM::YJIT) ? RubyVM::YJIT.enabled? : false)
    expect(document['trials'].length).to eq(1)
    expect(document['fps']).to eq(2.0)
  end
end

RSpec.describe 'rubyboy-bench executable' do
  let(:repository_root) { File.expand_path('..', __dir__) }

  it 'emits standalone JSON with the requested measured and warmup frame counts' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--count', '1', '--frames', '1', '--warmup-frames', '1', '--json', chdir: repository_root)

    expect(status.success?).to be(true), stderr
    document = JSON.parse(stdout)
    expect(document['frames']).to eq(1)
    expect(document['warmup_frames']).to eq(1)
    expect(document['total_frames']).to eq(1)
    expect(document['trials'].length).to eq(1)
    expect(document['render']).to be(false)
    expect(document['fps']).to be > 0
  end

  it 'rejects an invalid count with a failing exit status and no JSON output' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--count', '0', '--json', chdir: repository_root)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq('')
    expect(stderr).to include('count must be a positive integer')
  end

  %w[--count --frames --warmup-frames].each do |option|
    %w[abc 1.5].each do |value|
      it "rejects malformed #{option} #{value} without JSON or a stack trace" do
        stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', option, value, '--json', chdir: repository_root)

        expect(status.exitstatus).to eq(1)
        expect(stdout).to eq('')
        expect(stderr).to include('invalid')
        expect(stderr).not_to include('from ')
      end
    end
  end

  it 'rejects a negative warmup count instead of starting a trial' do
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, '-Ilib', 'exe/rubyboy-bench', '--warmup-frames', '-1', '--json', chdir: repository_root)

    expect(status.exitstatus).to eq(1)
    expect(stdout).to eq('')
    expect(stderr).to include('warmup_frames must be a nonnegative integer')
  end
end
