# frozen_string_literal: true

require 'js'
require 'json'

require_relative 'rubyboy/emulator_wasm'

class Executor
  def initialize
    rom_data = File.open('lib/roms/tobu.gb', 'r') { _1.read.bytes }
    @emulator = Rubyboy::EmulatorWasm.new(rom_data)
  end

  def exec
    bin = @emulator.step.pack('C*')
    File.binwrite(File.join('/OPTCARROT_TMP', 'video.data'), bin)
  end
end
