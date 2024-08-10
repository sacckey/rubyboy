# frozen_string_literal: true

require 'js'
require 'json'

require_relative 'rubyboy/emulator_wasm'

class Executor
  def initialize
    rom_data = File.open('lib/roms/tobu.gb', 'r') { _1.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def exec(direction_key = 0b1111, action_key = 0b1111)
    bin = @emulator.step(direction_key, action_key).pack('C*')
    File.binwrite(File.join('/RUBYBOY_TMP', 'video.data'), bin)
  end

  def read_rom_from_virtual_fs
    rom_path = '/RUBYBOY_TMP/rom.data'
    raise "ROM file not found in virtual filesystem at #{rom_path}" unless File.exist?(rom_path)

    rom_data = File.open(rom_path, 'rb') { |file| file.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end
end
