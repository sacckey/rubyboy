# frozen_string_literal: true

require_relative 'rubyboy/emulator_wasm'

class Executor
  ALLOWED_ROMS = ['tobu.gb', 'bgbtest.gb'].freeze

  def initialize(rom_path = '/lib/roms/tobu.gb')
    rom_data = File.binread(rom_path).bytes
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def exec(direction_key = 0b1111, action_key = 0b1111)
    @emulator.step(direction_key, action_key)
    write_framebuffer
    write_audio
    1
  end

  def read_rom_from_virtual_fs
    rom_path = '/rom.data'
    raise "ROM file not found in virtual filesystem at #{rom_path}" unless File.exist?(rom_path)

    rom_data = File.open(rom_path, 'rb') { |file| file.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def read_pre_installed_rom(rom_name)
    raise 'ROM not found in allowed ROMs' unless ALLOWED_ROMS.include?(rom_name)

    rom_path = File.join('/lib/roms', rom_name)
    rom_data = File.open(rom_path, 'r') { _1.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  private

  def write_framebuffer
    File.binwrite('/video.data', @emulator.framebuffer.pack('V*'))
  end

  def write_audio
    samples = @emulator.audio_samples
    File.binwrite('/audio.data', samples.pack('e*')) unless samples.empty?
  end
end
