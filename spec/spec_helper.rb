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

  def review(prompt, model:, report_file:)
    @calls << [:review, prompt, model, report_file]
  end

  def explore(prompt, model:, findings_file:)
    @calls << [:explore, prompt, model, findings_file]
  end

  def default_run_model
    'default-model'
  end

  def default_review_model
    'default-review-model'
  end

  def default_explore_model
    'default-explore-model'
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
