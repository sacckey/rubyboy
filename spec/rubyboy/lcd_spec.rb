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
    allow(Rubyboy::SDL).to receive(:RenderSetVSync).and_return(0)
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

  describe '#initialize' do
    it 'keeps the existing renderer configuration by default' do
      expect(Rubyboy::SDL).not_to receive(:RenderSetVSync)

      described_class.new
    end

    it 'disables VSync on the created renderer before preparing its texture' do
      expect(Rubyboy::SDL).to receive(:CreateRenderer).with(pointer, -1, 0).ordered.and_return(pointer)
      expect(Rubyboy::SDL).to receive(:RenderSetVSync).with(pointer, 0).ordered.and_return(0)
      expect(Rubyboy::SDL).to receive(:CreateTexture).ordered.and_return(pointer)

      described_class.new(vsync: false)
    end

    it 'can explicitly enable VSync' do
      expect(Rubyboy::SDL).to receive(:RenderSetVSync).with(pointer, 1).and_return(0)

      described_class.new(vsync: true)
    end

    it 'fails if the renderer cannot apply the requested VSync setting' do
      allow(Rubyboy::SDL).to receive(:RenderSetVSync).and_return(-1)
      allow(Rubyboy::SDL).to receive(:GetError).and_return('VSync is unsupported')
      expect(Rubyboy::SDL).not_to receive(:CreateTexture)
      expect(Rubyboy::SDL).to receive(:DestroyWindow).with(pointer)
      expect(Rubyboy::SDL).to receive(:Quit)

      expect { described_class.new(vsync: false) }.to raise_error(RuntimeError, 'VSync is unsupported')
    end

    it 'reports renderer creation failures before trying to configure VSync' do
      allow(Rubyboy::SDL).to receive(:CreateRenderer).and_return(FFI::Pointer::NULL)
      allow(Rubyboy::SDL).to receive(:GetError).and_return('Renderer creation failed')
      expect(Rubyboy::SDL).not_to receive(:RenderSetVSync)
      expect(Rubyboy::SDL).not_to receive(:CreateTexture)
      expect(Rubyboy::SDL).to receive(:DestroyWindow).with(pointer)
      expect(Rubyboy::SDL).to receive(:Quit)

      expect { described_class.new(vsync: false) }.to raise_error(RuntimeError, 'Renderer creation failed')
    end
  end
end
