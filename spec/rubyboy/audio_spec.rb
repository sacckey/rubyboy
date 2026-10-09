# frozen_string_literal: true

RSpec.describe Rubyboy::Audio do
  describe '#queue' do
    let(:audio) { described_class.allocate.tap { _1.instance_variable_set(:@device, 42) } }

    before { allow(Rubyboy::SDL).to receive(:QueueAudio) }

    it 'waits for a full queue to drain by default' do
      allow(Rubyboy::SDL).to receive(:GetQueuedAudioSize).with(42).and_return(8193, 0)
      allow(audio).to receive(:sleep)

      audio.queue([0.5, -0.5])

      expect(audio).to have_received(:sleep).once
      expect(Rubyboy::SDL).to have_received(:QueueAudio).once
    end

    it 'drops the buffer instead of waiting when wait is false' do
      allow(Rubyboy::SDL).to receive(:GetQueuedAudioSize).with(42).and_return(8193)
      expect(audio).not_to receive(:sleep)

      audio.queue([0.5, -0.5], wait: false)

      expect(Rubyboy::SDL).not_to have_received(:QueueAudio)
    end
  end

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
