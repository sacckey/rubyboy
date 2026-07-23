# frozen_string_literal: true

RSpec.describe Rubyboy::Audio do
  describe '#clear_queue' do
    it 'clears queued audio for its SDL device' do
      audio = described_class.allocate
      audio.instance_variable_set(:@device, 42)
      allow(Rubyboy::SDL).to receive(:ClearQueuedAudio)

      audio.clear_queue

      expect(Rubyboy::SDL).to have_received(:ClearQueuedAudio).with(42)
    end
  end
end
