# frozen_string_literal: true

require_relative 'lib/rubyboy/version'

Gem::Specification.new do |spec|
  spec.name = 'rubyboy'
  spec.version = Rubyboy::VERSION
  spec.authors = ['sacckey']

  spec.summary = 'A Game Boy emulator written in Ruby'
  spec.homepage = 'https://github.com/sacckey/rubyboy'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.2.0'

  spec.metadata['allowed_push_host'] = 'https://rubygems.org'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['changelog_uri'] = 'https://github.com/sacckey/rubyboy/blob/main/CHANGELOG.md'
  spec.metadata['rubygems_mfa_required'] = 'true'

  # Ship only the runtime code, the default ROM and top-level documents.
  # Test ROMs and the browser builds stay in the repository.
  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z lib exe LICENSE.txt README.md CHANGELOG.md`.split("\x0").reject do |f|
      f.start_with?('lib/roms/') && f != 'lib/roms/tobu.gb'
    end
  end
  spec.bindir = 'exe'
  spec.executables = %w[rubyboy rubyboy-bench]
  spec.require_paths = ['lib']

  # Uncomment to register a new dependency of your gem
  spec.add_dependency 'ffi', '~> 1.16', '>= 1.16.3'

  # For more information and examples about making a new gem, check out our
  # guide at: https://bundler.io/guides/creating_gem.html
end
