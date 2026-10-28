# frozen_string_literal: true

module Planner
  module Agents
    # Wraps the `claude` CLI. The interface (#plan, #run, #review, #default_run_model,
    # #default_review_model) is the contract a future agent must implement.
    class Claude
      PLAN_MODEL = 'opus'
      DEFAULT_RUN_MODEL = 'sonnet'
      DEFAULT_REVIEW_MODEL = 'opus'
      REVIEW_TOOLS = 'Read,Grep,Glob,Write'

      def initialize(executor: Kernel.method(:exec))
        @executor = executor
      end

      def plan(prompt)
        @executor.call('claude', '--model', PLAN_MODEL, prompt)
      end

      def run(prompt, model:)
        @executor.call('claude', '--model', model, prompt)
      end

      def review(prompt, model:, report_file:)
        @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                       "--allowedTools=Edit(#{report_file})", prompt)
      end

      def default_run_model
        DEFAULT_RUN_MODEL
      end

      def default_review_model
        DEFAULT_REVIEW_MODEL
      end
    end
  end
end
