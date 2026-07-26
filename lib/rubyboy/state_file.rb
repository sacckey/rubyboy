# frozen_string_literal: true

module Rubyboy
  class StateFile
    MAGIC = 'RBYSTATE'
    FORMAT_VERSION = 1
    HEADER_SIZE = 16

    def self.write(path, rom:)
      payload = Marshal.dump(yield)
      header = MAGIC.b + [FORMAT_VERSION, rom.global_checksum_value, 0].pack('L<S<S<')
      tmp_path = "#{path}.tmp"
      File.binwrite(tmp_path, header + payload)
      File.rename(tmp_path, path)
      true
    rescue StandardError => e
      warn "[rubyboy] failed to write state file #{path}: #{e.message}"
      false
    end

    def self.read(path, rom:)
      return warn_and_false("state file does not exist: #{path}") unless File.exist?(path)

      data = File.binread(path)
      return warn_and_false("state file is too small: #{path}") if data.bytesize < HEADER_SIZE

      magic = data.byteslice(0, MAGIC.bytesize)
      return warn_and_false("invalid state file magic: #{path}") unless magic == MAGIC

      version, checksum = data.byteslice(8, 6).unpack('L<S<')
      return warn_and_false("unsupported state file version #{version} (expected #{FORMAT_VERSION})") unless version == FORMAT_VERSION
      return warn_and_false("ROM checksum mismatch for state file #{path}") unless checksum == rom.global_checksum_value

      # State files are local emulator snapshots written by this process.
      # rubocop:disable Security/MarshalLoad
      yield Marshal.load(data.byteslice(HEADER_SIZE..))
      # rubocop:enable Security/MarshalLoad
      true
    rescue StandardError => e
      warn "[rubyboy] failed to read state file #{path}: #{e.message}"
      false
    end

    def self.warn_and_false(message)
      warn "[rubyboy] #{message}"
      false
    end
    private_class_method :warn_and_false
  end
end
