# frozen_string_literal: true

require_relative 'lib/planner/version'

Gem::Specification.new do |spec|
  spec.name = 'planner'
  spec.version = Planner::VERSION
  spec.authors = ['Colin Gemmell']
  spec.email = ['pythonandchips@gmail.com']
  spec.summary = 'Create plan folders and hand iteration and plan files to a coding agent.'
  spec.required_ruby_version = '>= 3.4'

  # Points at an unusable host so the gem can never be pushed to rubygems.org.
  spec.metadata['allowed_push_host'] = 'https://gems.invalid'
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files = Dir['lib/**/*.rb', 'lib/**/*.erb', 'lib/planner/skills/**/*', 'exe/*', 'README.md']
               .select { |path| File.file?(path) }
  spec.bindir = 'exe'
  spec.executables = ['planner']
  spec.require_paths = ['lib']
end
