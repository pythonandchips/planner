# frozen_string_literal: true

module Planner
  module Agents
    # Wraps the `claude` CLI. The interface (#plan, #run, #run_tools, #review, #explore, #summarise, #toc,
    # #default_run_model, #default_review_model, #default_explore_model, #default_summarise_model,
    # #default_toc_model) is the contract a future agent must implement.
    class Claude
      PLAN_MODEL = 'opus'
      DEFAULT_RUN_MODEL = 'sonnet'
      RUN_TOOLS = %w[Bash Read Edit Write Glob Grep Skill].freeze
      DEFAULT_REVIEW_MODEL = 'opus'
      REVIEW_TOOLS = 'Read,Grep,Glob,Write'
      DEFAULT_EXPLORE_MODEL = 'opus'
      EXPLORE_TOOLS = 'Read,Grep,Glob,Write,WebFetch'
      DEFAULT_SUMMARISE_MODEL = 'opus'
      SUMMARISE_TOOLS = 'Read,Grep,Glob,Write,Bash,WebFetch,Skill'
      DEFAULT_TOC_MODEL = 'haiku'
      TOC_TOOLS = 'Read,Grep,Glob,Write'

      def initialize(executor: Kernel.method(:exec))
        @executor = executor
      end

      def plan(prompt)
        @executor.call('claude', '--model', PLAN_MODEL, prompt)
      end

      def run(prompt, model:)
        @executor.call('claude', '--model', model, prompt)
      end

      def review(prompt, model:, report_file:, plan_file:, toc_file:)
        @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                       "--allowedTools=Edit(#{report_file}),Edit(#{plan_file}),Edit(#{toc_file})", prompt)
      end

      def explore(prompt, model:, findings_file:, toc_file:)
        @executor.call('claude', '--model', model, "--tools=#{EXPLORE_TOOLS}",
                       "--allowedTools=Edit(#{findings_file}),Edit(#{toc_file}),WebFetch", prompt)
      end

      def summarise(prompt, model:, summary_base:, toc_file:)
        @executor.call('claude', '--model', model, "--tools=#{SUMMARISE_TOOLS}",
                       "--allowedTools=Edit(#{summary_base}.*),Edit(#{summary_base}/**),Edit(#{toc_file})", prompt)
      end

      def toc(prompt, model:, toc_file:)
        @executor.call('claude', '-p', '--model', model, "--tools=#{TOC_TOOLS}",
                       "--allowedTools=Edit(#{toc_file})", prompt)
      end

      def default_run_model
        DEFAULT_RUN_MODEL
      end

      def run_tools
        RUN_TOOLS
      end

      def default_review_model
        DEFAULT_REVIEW_MODEL
      end

      def default_explore_model
        DEFAULT_EXPLORE_MODEL
      end

      def default_summarise_model
        DEFAULT_SUMMARISE_MODEL
      end

      def default_toc_model
        DEFAULT_TOC_MODEL
      end
    end
  end
end
