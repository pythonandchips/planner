# frozen_string_literal: true

require 'planner'
require 'tmpdir'

# Records calls instead of launching a coding agent.
class FakeAgent
  attr_reader :calls

  def initialize
    @calls = []
  end

  def plan(prompt)
    @calls << [:plan, prompt]
  end

  def run(prompt, model:)
    @calls << [:run, prompt, model]
  end

  def default_run_model
    'default-model'
  end
end

RSpec.configure do |config|
  config.example_status_persistence_file_path = '.rspec_status'
  config.disable_monkey_patching!
  config.expect_with(:rspec) { |c| c.syntax = :expect }

  config.around do |example|
    Dir.mktmpdir { |dir| Dir.chdir(dir) { example.run } }
  end
end
