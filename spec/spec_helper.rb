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

  def review(prompt, model:, report_file:, plan_file:, toc_file:)
    @calls << [:review, prompt, model, report_file, plan_file, toc_file]
  end

  def explore(prompt, model:, findings_file:, toc_file:)
    @calls << [:explore, prompt, model, findings_file, toc_file]
  end

  def explore_deep(prompt, model:, findings_file:, toc_file:)
    @calls << [:explore_deep, prompt, model, findings_file, toc_file]
  end

  def summarise(prompt, model:, summary_base:, toc_file:)
    @calls << [:summarise, prompt, model, summary_base, toc_file]
  end

  def toc(prompt, model:, toc_file:)
    @calls << [:toc, prompt, model, toc_file]
  end

  def default_run_model
    'default-model'
  end

  def run_tools
    %w[Tool]
  end

  def default_review_model
    'default-review-model'
  end

  def default_explore_model
    'default-explore-model'
  end

  def default_summarise_model
    'default-summarise-model'
  end

  def default_toc_model
    'default-toc-model'
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
