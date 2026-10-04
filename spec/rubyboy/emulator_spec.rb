# frozen_string_literal: true

RSpec.describe Rubyboy::Emulator do
  describe 'command line' do
    let(:executable) { File.expand_path('../../exe/rubyboy', __dir__) }

    it 'converts the frame count and forwards playback options' do
      emulator = instance_double(described_class, start: nil)
      stub_const('ARGV', %w[--frames 3 --unlimited --no-audio game.gb])
      expect(described_class).to receive(:new).with('game.gb', audio: false).and_return(emulator)

      load executable

      expect(emulator).to have_received(:start).with(frames: 3, realtime: false)
    end

    it 'rejects invalid frame counts before creating the emulator' do
      expect(described_class).not_to receive(:new)

      %w[0 -1 1.5 invalid].each do |frames|
        stub_const('ARGV', ['--frames', frames])

        expect { load executable }.to raise_error(SystemExit) { |error| expect(error.status).to eq(1) }
      end
    end
  end

  describe '#initialize' do
    it 'does not open an audio device when audio output is disabled' do
      rom_path = File.expand_path('../../lib/roms/hello-world.gb', __dir__)
      allow(Rubyboy::Lcd).to receive(:new).and_return(instance_double(Rubyboy::Lcd))
      expect(Rubyboy::Audio).not_to receive(:new)

      described_class.new(rom_path, audio: false)
    end

    it 'opens an audio device by default' do
      rom_path = File.expand_path('../../lib/roms/hello-world.gb', __dir__)
      allow(Rubyboy::Lcd).to receive(:new).and_return(instance_double(Rubyboy::Lcd))
      expect(Rubyboy::Audio).to receive(:new).and_return(instance_double(Rubyboy::Audio))

      described_class.new(rom_path)
    end
  end

  describe '#start' do
    let(:emulator) { described_class.allocate }
    let(:cpu) { instance_double(Rubyboy::Cpu, exec: 4) }
    let(:timer) { instance_double(Rubyboy::Timer, step: nil) }
    let(:apu) { instance_double(Rubyboy::Apu, step: true, samples: [0.25, -0.25]) }
    let(:ppu) { instance_double(Rubyboy::Ppu, step: true, buffer: [0]) }
    let(:audio) { instance_double(Rubyboy::Audio, queue: nil) }
    let(:lcd) { instance_double(Rubyboy::Lcd, draw: nil, close_window: nil, window_should_close?: false) }

    before do
      emulator.instance_variable_set(:@cpu, cpu)
      emulator.instance_variable_set(:@timer, timer)
      emulator.instance_variable_set(:@apu, apu)
      emulator.instance_variable_set(:@ppu, ppu)
      emulator.instance_variable_set(:@audio, audio)
      emulator.instance_variable_set(:@lcd, lcd)
      allow(emulator).to receive(:key_input_check)
      allow(emulator).to receive(:save_save_file)
      allow(Rubyboy::SDL).to receive(:InitSubSystem)
    end

    it 'stops after drawing exactly the requested number of completed PPU frames' do
      allow(ppu).to receive(:step).and_return(false, true, false, true, true)
      expect(Process).not_to receive(:clock_gettime)

      emulator.start(frames: 3, realtime: false)

      expect(cpu).to have_received(:exec).exactly(5).times
      expect(timer).to have_received(:step).with(4).exactly(5).times
      expect(apu).to have_received(:step).with(4).exactly(5).times
      expect(lcd).to have_received(:draw).with([0]).exactly(3).times
      expect(emulator).to have_received(:key_input_check).exactly(3).times
      expect(lcd).to have_received(:close_window).once
      expect(emulator).to have_received(:save_save_file).once
    end

    it 'continues synthesizing audio when audio output is disabled' do
      emulator.instance_variable_set(:@audio, nil)

      emulator.start(frames: 2, realtime: false)

      expect(apu).to have_received(:step).with(4).twice
      expect(apu).not_to have_received(:samples)
      expect(audio).not_to have_received(:queue)
      expect(lcd).to have_received(:draw).twice
    end

    it 'queues synthesized audio when audio output is enabled' do
      emulator.start(frames: 2, realtime: false)

      expect(audio).to have_received(:queue).with([0.25, -0.25]).twice
    end

    it 'synchronizes to real time by default and can stop after a finite frame count' do
      allow(Process).to receive(:clock_gettime).with(Process::CLOCK_MONOTONIC, :nanosecond).and_return(0, 0, 2000)

      emulator.start(frames: 2)

      expect(Process).to have_received(:clock_gettime).exactly(3).times
      expect(cpu).to have_received(:exec).twice
      expect(lcd).to have_received(:draw).twice
    end

    it 'continues until the window closes when no frame count is specified' do
      allow(lcd).to receive(:window_should_close?).and_return(false, true)

      emulator.start(realtime: false)

      expect(lcd).to have_received(:draw).twice
      expect(lcd).to have_received(:close_window).once
    end

    it 'honors a window close before reaching the requested frame count' do
      allow(lcd).to receive(:window_should_close?).and_return(true)

      emulator.start(frames: 10, realtime: false)

      expect(lcd).to have_received(:draw).once
    end

    it 'closes the window and saves battery RAM if execution fails' do
      allow(cpu).to receive(:exec).and_raise('execution failed')

      expect { emulator.start(frames: 2, realtime: false) }.to raise_error(RuntimeError, 'execution failed')

      expect(lcd).to have_received(:close_window).once
      expect(emulator).to have_received(:save_save_file).once
    end

    it 'rejects nonpositive and noninteger frame counts before running the CPU' do
      [0, -1, 1.5, '2'].each do |frames|
        expect { emulator.start(frames:, realtime: false) }.to raise_error(ArgumentError, 'frames must be a positive integer')
      end

      expect(cpu).not_to have_received(:exec)
      expect(lcd).not_to have_received(:draw)
      expect(lcd).not_to have_received(:close_window)
      expect(emulator).not_to have_received(:save_save_file)
    end
  end

  describe 'save state key handling' do
    it 'uses the number printed on each key as the slot number' do
      expected_slots = [1, 2, 3, 4, 5, 6, 7, 8, 9, 0]

      described_class::SAVE_STATE_KEYS.zip(expected_slots).each do |key, slot|
        emulator = described_class.allocate
        emulator.instance_variable_set(:@prev_save_state_keys, Array.new(described_class::SAVE_STATE_KEYS.size, 0))
        keyboard_state = Array.new(229, 0)
        keyboard_state[key] = 1
        allow(emulator).to receive(:save_state)

        emulator.send(:check_state_save_keys, keyboard_state)

        expect(emulator).to have_received(:save_state).with(slot:)
      end
    end
  end

  describe '#load_state' do
    it 'clears queued audio after loading succeeds' do
      emulator = described_class.allocate
      audio = instance_double(Rubyboy::Audio, clear_queue: nil)
      emulator.instance_variable_set(:@rom, instance_double(Rubyboy::Rom))
      emulator.instance_variable_set(:@audio, audio)
      allow(Rubyboy::StateFile).to receive(:read).and_return(true)

      expect(emulator.load_state(path: 'game.state1')).to be true

      expect(audio).to have_received(:clear_queue)
    end

    it 'can load a state when audio output is disabled' do
      emulator = described_class.allocate
      emulator.instance_variable_set(:@rom, instance_double(Rubyboy::Rom))
      emulator.instance_variable_set(:@audio, nil)
      allow(Rubyboy::StateFile).to receive(:read).and_return(true)

      expect(emulator.load_state(path: 'game.state1')).to be true
    end
  end
end
