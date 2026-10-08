# frozen_string_literal: true

require_relative '../lib/executor'

# Export the existing browser executor; all emulation and output stay in Ruby.
module RubyboyBrowser
  def self.init(rom_path)
    @executor = Executor.new(rom_path)
    true
  end

  def self.exec(direction, action)
    @executor.exec(direction, action)
  end

  def self.read_rom_from_virtual_fs
    @executor.read_rom_from_virtual_fs
    true
  end

  def self.read_pre_installed_rom(name)
    @executor.read_pre_installed_rom(name)
    true
  end
end

# Concrete call-site types for the exported entry points; excluded from Wasm init.
if __FILE__ == $PROGRAM_NAME
  RubyboyBrowser.init(File.expand_path('../lib/roms/tobu.gb', __dir__))
  p RubyboyBrowser.exec(15, 15)
  p RubyboyBrowser.read_pre_installed_rom('tobu.gb')
  p RubyboyBrowser.read_rom_from_virtual_fs
end
