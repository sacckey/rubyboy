# frozen_string_literal: true

require 'js'
require 'json'

require_relative 'rubyboy/emulator_wasm'

class Executor
  ALLOWED_ROMS = ['tobu.gb', 'bgbtest.gb'].freeze

  def initialize
    rom_data = File.open('lib/roms/tobu.gb', 'r') { _1.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def exec(direction_key = 0b1111, action_key = 0b1111)
    bin = @emulator.step(direction_key, action_key).pack('V*')
    File.binwrite(File.join('/RUBYBOY_TMP', 'video.data'), bin)
  end

  def read_rom_from_virtual_fs
    rom_path = '/RUBYBOY_TMP/rom.data'
    raise "ROM file not found in virtual filesystem at #{rom_path}" unless File.exist?(rom_path)

    rom_data = File.open(rom_path, 'rb') { |file| file.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def read_pre_installed_rom(rom_name)
    raise 'ROM not found in allowed ROMs' unless ALLOWED_ROMS.include?(rom_name)

    rom_path = File.join('lib/roms', rom_name)
    rom_data = File.open(rom_path, 'r') { _1.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end
end
