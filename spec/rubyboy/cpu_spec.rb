# frozen_string_literal: true

RSpec.describe Rubyboy::Cpu do
  let(:memory) { Array.new(0x10000, 0) }
  let(:cpu) do
    bus = instance_double(Rubyboy::Bus)
    allow(bus).to receive(:read_byte) { |addr| memory[addr] }
    allow(bus).to receive(:read_word) { |addr| memory[addr] | (memory[addr + 1] << 8) }
    allow(bus).to receive(:write_byte) { |addr, value| memory[addr] = value }
    described_class.new(bus, Rubyboy::Interrupt.new)
  end

  # LD HL, 0xc000, then the CB-prefixed rotate eight times: the byte comes back.
  def rotate_hl_eight_times(cb_opcode, value)
    program = [0x21, 0x00, 0xc0] + ([0xcb, cb_opcode] * 8)
    memory[0x0100, program.size] = program
    memory[0xc000] = value
    9.times { cpu.exec }
    memory[0xc000]
  end

  it 'keeps RLC (HL) within a byte' do
    expect(rotate_hl_eight_times(0x06, 0x81)).to eq(0x81)
  end

  it 'keeps RRC (HL) within a byte' do
    expect(rotate_hl_eight_times(0x0e, 0x81)).to eq(0x81)
  end
end
