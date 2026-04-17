# frozen_string_literal: true

module Rubyboy
  class SaveFile
    attr_reader :path

    def initialize(path)
      @path = path
    end

    def read(expected_size)
      return nil unless File.exist?(@path)

      bytes = File.binread(@path).bytes
      if bytes.size != expected_size
        warn "[rubyboy] save file size mismatch (expected #{expected_size} bytes, got #{bytes.size}); ignoring #{@path}"
        return nil
      end

      bytes
    rescue StandardError => e
      warn "[rubyboy] failed to read save file #{@path}: #{e.message}"
      nil
    end

    def write(bytes)
      tmp_path = "#{@path}.tmp"
      File.binwrite(tmp_path, bytes.pack('C*'))
      File.rename(tmp_path, @path)
      true
    rescue StandardError => e
      warn "[rubyboy] failed to write save file #{@path}: #{e.message}"
      false
    end
  end
end
