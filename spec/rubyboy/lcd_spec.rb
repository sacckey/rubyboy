# frozen_string_literal: true

RSpec.describe Rubyboy::Lcd do
  let(:pointer) { FFI::MemoryPointer.new(:uint8) }

  before do
    allow(Rubyboy::SDL).to receive(:InitSubSystem).and_return(0)
    allow(Rubyboy::SDL).to receive(:CreateWindow).and_return(pointer)
    allow(Rubyboy::SDL).to receive(:CreateRenderer).and_return(pointer)
    allow(Rubyboy::SDL).to receive(:CreateTexture).and_return(pointer)
    allow(Rubyboy::SDL).to receive(:SetHint)
    allow(Rubyboy::SDL).to receive(:RenderSetLogicalSize)
    allow(Rubyboy::SDL).to receive(:DestroyWindow)
    allow(Rubyboy::SDL).to receive(:Quit)
  end

  it 'provides enough event storage for SDL_PollEvent' do
    allow(Rubyboy::SDL).to receive(:PollEvent) do |event|
      # SDL2's event union includes 56 bytes of padding on 32/64-bit hosts.
      event.put_bytes(0, "\x00" * 56)
      event.write_int(Rubyboy::SDL::QUIT)
      1
    end

    lcd = described_class.new

    expect(lcd.window_should_close?).to be(true)
  end
end
