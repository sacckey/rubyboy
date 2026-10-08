#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require_relative '../lib/rubyboy/emulator_wasm'

rom_path = File.expand_path('../lib/roms/tobu.gb', __dir__)
rom = File.binread(rom_path).bytes
checkpoints = [1, 2, 15, 30, 45, 60]

def input_for(tick)
  direction = tick.between?(50, 53) ? 14 : 15
  action = if tick.between?(10, 13)
             7 # Start, active-low.
           elsif tick.between?(40, 45)
             14 # A, active-low.
           else
             15
           end
  [direction, action]
end

def run_reference(rom, checkpoints)
  emulator = Rubyboy::EmulatorWasm.new(rom)
  accumulated_audio = +''.b
  frames = 0
  results = []
  60.times do |index|
    tick = index + 1
    direction, action = input_for(tick)
    emulator.step(direction, action)
    frames += 1
    audio = emulator.audio_samples.pack('e*')
    accumulated_audio << audio
    next unless checkpoints.include?(tick)

    results << {
      tick:,
      frames:,
      video_sha256: Digest::SHA256.hexdigest(emulator.framebuffer.pack('V*')),
      audio_sha256: Digest::SHA256.hexdigest(audio),
      audio_bytes: audio.bytesize,
      accumulated_audio_sha256: Digest::SHA256.hexdigest(accumulated_audio),
      accumulated_audio_bytes: accumulated_audio.bytesize
    }
  end
  results
end

puts JSON.generate({
                     ruby: RUBY_DESCRIPTION,
                     rom_sha256: Digest::SHA256.file(rom_path).hexdigest,
                     ticks: 60,
                     inputs: (1..60).map { |tick| input_for(tick) },
                     checkpoints: run_reference(rom, checkpoints)
                   })
