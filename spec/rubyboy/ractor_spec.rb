# frozen_string_literal: true

RSpec.describe 'Constants used while emulating' do
  it 'can be shared with other Ractors' do
    expect(Ractor.shareable?(Rubyboy::ApuChannels::Channel1::WAVE_DUTY)).to be(true)
    expect(Ractor.shareable?(Rubyboy::ApuChannels::Channel2::WAVE_DUTY)).to be(true)
    expect(Ractor.shareable?(Rubyboy::Rom::DEFAULT_PATH)).to be(true)
  end
end
