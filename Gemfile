# frozen_string_literal: true

source 'https://rubygems.org'

# Specify your gem's dependencies in rubyboy.gemspec
gemspec

gem 'rake', '~> 13.0'

group :development, :test do
  # These bundled gems are required by older RuboCop on recent Ruby versions.
  gem 'benchmark'
  gem 'ostruct'
  gem 'rspec', '~> 3.12'
  gem 'rubocop', '~> 1.57'
end

group :wasm do
  gem 'js', '2.10.1'
  gem 'ruby_wasm', '2.10.1'
end
