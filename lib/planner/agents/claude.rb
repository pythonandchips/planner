# frozen_string_literal: true

module Planner
  module Agents
    # Wraps the `claude` CLI. The interface (#plan, #run, #default_run_model) is the
    # contract a future agent must implement.
    class Claude
      PLAN_MODEL = 'opus'
      DEFAULT_RUN_MODEL = 'sonnet'

      def initialize(executor: Kernel.method(:exec))
        @executor = executor
      end

      def plan(prompt)
        @executor.call('claude', '--model', PLAN_MODEL, prompt)
      end

      def run(prompt, model:)
        @executor.call('claude', '--model', model, prompt)
      end

      def default_run_model
        DEFAULT_RUN_MODEL
      end
    end
  end
end
