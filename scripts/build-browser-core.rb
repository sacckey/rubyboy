#!/usr/bin/env ruby
# frozen_string_literal: true

require 'digest'
require 'json'
require 'pathname'

root = File.expand_path('..', __dir__)
lib_dir = File.join(root, 'lib')
pending = ['executor.rb']
sources = {}

until pending.empty?
  relative_path = pending.shift
  next if sources.key?(relative_path)

  path = File.expand_path(relative_path, lib_dir)
  raise "Ruby source escaped lib/: #{relative_path}" unless path.start_with?(lib_dir + File::SEPARATOR)

  source = File.read(path, encoding: 'UTF-8')
  sources[relative_path] = source
  source.scan(/^\s*require_relative\s+['"]([^'"]+)['"]/).each do |match|
    dependency = File.expand_path("#{match.first}.rb", File.dirname(path))
    pending << Pathname.new(dependency).relative_path_from(Pathname.new(lib_dir)).to_s
  end
end

bundle = {
  api_version: 1,
  generator_ruby: RUBY_VERSION,
  files: sources.sort.map do |source_path, contents|
    { path: source_path, sha256: Digest::SHA256.hexdigest(contents), source: contents }
  end
}
output = File.join(root, 'docs', 'rubyboy-core.json')
File.write(output, "#{JSON.generate(bundle)}\n")
puts "Wrote #{output} (#{bundle[:files].length} Ruby files, #{File.size(output)} bytes)"
