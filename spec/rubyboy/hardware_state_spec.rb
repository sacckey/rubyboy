# frozen_string_literal: true

RSpec.describe 'hardware state snapshots' do
  def rom_with_ram_size(byte)
    instance_double(Rubyboy::Rom, ram_size_bytes: Rubyboy::Rom::RAM_SIZE_BYTES.fetch(byte))
  end

  it 'round-trips RAM arrays without sharing mutable storage' do
    ram = Rubyboy::Ram.new(rom_with_ram_size(0x02))
    ram.eram[0] = 0x42
    state = ram.hardware_state
    ram.eram[0] = 0x99

    ram.restore_hardware_state(state)

    expect(ram.eram[0]).to eq(0x42)
    state[:eram][0] = 0x11
    expect(ram.eram[0]).to eq(0x42)
  end

  it 'round-trips MBC1 register state' do
    rom = instance_double(Rubyboy::Rom, data: Array.new(128 * 0x4000) { |i| i / 0x4000 })
    ram = instance_double(Rubyboy::Ram, eram: Array.new(32 * 1024, 0))
    mbc = Rubyboy::Cartridge::Mbc1.new(rom, ram)
    mbc.write_byte(0x0000, 0x0a)
    mbc.write_byte(0x2000, 0x03)
    mbc.write_byte(0x4000, 0x02)
    mbc.write_byte(0x6000, 0x01)
    state = mbc.hardware_state

    restored = Rubyboy::Cartridge::Mbc1.new(rom, ram)
    restored.restore_hardware_state(state)

    expect(restored.read_byte(0x4000)).to eq(mbc.read_byte(0x4000))
  end

  it 'rebuilds PPU render caches from VRAM/OAM/register state' do
    ppu = Rubyboy::Ppu.new(Rubyboy::Interrupt.new)
    ppu.instance_variable_set(:@mode, Rubyboy::Ppu::MODE[:hblank])
    ppu.write_byte(0x8000, 0xff)
    ppu.write_byte(0x8001, 0x00)
    ppu.write_byte(0xfe00, 0x22)
    ppu.write_byte(0xff47, 0xe4)
    state = ppu.hardware_state

    restored = Rubyboy::Ppu.new(Rubyboy::Interrupt.new)
    restored.restore_hardware_state(state)

    expect(restored.read_byte(0x8000)).to eq(0xff)
    expect(restored.read_byte(0xfe00)).to eq(0x22)
    expect(restored.instance_variable_get(:@tile_cache)[0][0]).to eq(1)
    expect(restored.instance_variable_get(:@sprite_cache)[0][:y]).to eq(0x12)
    expect(restored.buffer).to eq(Array.new(144 * 160, 0xffffffff))
  end

  describe 'APU channel snapshots' do
    shared_examples 'a compatible channel snapshot' do |channel_class, fields|
      it 'preserves the saved field set and restores non-default values' do
        channel = channel_class.new
        expect(channel.hardware_state.keys).to match_array(channel.instance_variables.map { _1.to_s.delete_prefix('@').to_sym })

        expected = fields.each_with_index.to_h do |field, index|
          initial = channel.instance_variable_get("@#{field}")
          value = case initial
                  when true, false then !initial
                  when Array then initial.each_index.map { |i| (i * 17) & 0xff }
                  else index + 1
                  end
          channel.instance_variable_set("@#{field}", value)
          [field, value]
        end

        state = channel.hardware_state

        expect(state.keys).to match_array(fields)
        expect(state).to eq(expected)

        restored = channel_class.new
        restored.restore_hardware_state(state)

        expected.each do |field, value|
          expect(restored.instance_variable_get("@#{field}")).to eq(value)
        end
      end
    end

    context 'channel 1' do
      include_examples 'a compatible channel snapshot', Rubyboy::ApuChannels::Channel1, %i[
        cycles frequency frequency_timer wave_duty_position enabled dac_enabled length_enabled
        is_upwards is_decrementing sweep_enabled sweep_period sweep_shift period period_timer
        current_volume initial_volume shadow_frequency sweep_timer length_timer wave_duty_pattern
      ]
    end

    context 'channel 2' do
      include_examples 'a compatible channel snapshot', Rubyboy::ApuChannels::Channel2, %i[
        cycles frequency frequency_timer wave_duty_position enabled dac_enabled length_enabled
        is_upwards is_decrementing period period_timer current_volume initial_volume shadow_frequency
        length_timer wave_duty_pattern
      ]
    end

    context 'channel 3' do
      include_examples 'a compatible channel snapshot', Rubyboy::ApuChannels::Channel3, %i[
        cycles frequency frequency_timer wave_duty_position enabled dac_enabled length_enabled
        is_upwards is_decrementing sweep_enabled sweep_period sweep_shift period period_timer
        current_volume initial_volume shadow_frequency sweep_timer length_timer wave_duty_pattern
        output_level volume_shift wave_ram
      ]

      it 'keeps wave RAM independent when snapshotting and restoring' do
        channel = Rubyboy::ApuChannels::Channel3.new
        channel.wave_ram[0] = 0x42
        state = channel.hardware_state
        channel.wave_ram[0] = 0x99

        expect(state.fetch(:wave_ram)[0]).to eq(0x42)

        channel.restore_hardware_state(state)
        state.fetch(:wave_ram)[0] = 0x11

        expect(channel.wave_ram[0]).to eq(0x42)
      end
    end

    context 'channel 4' do
      include_examples 'a compatible channel snapshot', Rubyboy::ApuChannels::Channel4, %i[
        cycles frequency frequency_timer wave_duty_position enabled dac_enabled length_enabled
        is_upwards is_decrementing sweep_enabled sweep_period sweep_shift period period_timer
        current_volume initial_volume shadow_frequency sweep_timer length_timer wave_duty_pattern
        lfsr width_mode shift_amount divisor_code
      ]
    end
  end
end
