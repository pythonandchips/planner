# frozen_string_literal: true

module Planner
  module Agents
    # Wraps the `claude` CLI. The interface (#plan, #run, #review, #explore, #default_run_model,
    # #default_review_model, #default_explore_model) is the contract a future agent must implement.
    class Claude
      PLAN_MODEL = 'opus'
      DEFAULT_RUN_MODEL = 'sonnet'
      DEFAULT_REVIEW_MODEL = 'opus'
      REVIEW_TOOLS = 'Read,Grep,Glob,Write'
      DEFAULT_EXPLORE_MODEL = 'opus'
      EXPLORE_TOOLS = 'Read,Grep,Glob,Write'

      def initialize(executor: Kernel.method(:exec))
        @executor = executor
      end

      def plan(prompt)
        @executor.call('claude', '--model', PLAN_MODEL, prompt)
      end

      def run(prompt, model:)
        @executor.call('claude', '--model', model, prompt)
      end

      def review(prompt, model:, report_file:, plan_file:)
        @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                       "--allowedTools=Edit(#{report_file}),Edit(#{plan_file})", prompt)
      end

      def explore(prompt, model:, findings_file:)
        @executor.call('claude', '--model', model, "--tools=#{EXPLORE_TOOLS}",
                       "--allowedTools=Edit(#{findings_file})", prompt)
      end

      def default_run_model
        DEFAULT_RUN_MODEL
      end

      def default_review_model
        DEFAULT_REVIEW_MODEL
      end

      def default_explore_model
        DEFAULT_EXPLORE_MODEL
      end
    end
  end
end
