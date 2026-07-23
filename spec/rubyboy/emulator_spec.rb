# frozen_string_literal: true

RSpec.describe Rubyboy::Emulator do
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
  end
end
