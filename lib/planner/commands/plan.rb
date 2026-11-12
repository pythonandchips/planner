# frozen_string_literal: true

module Planner
  module Commands
    # Renders the plan prompt for an iteration file and hands it to the agent.
    class Plan
      TEMPLATE = File.expand_path('../prompts/plan.md.erb', __dir__)
      ITERATION_NAME = /\AITERATION-(\d+)\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        file = args.first
        raise UsageError if file.nil? || file.empty?

        number = File.basename(file)[ITERATION_NAME, 1]
        raise Error, "#{file} is not an ITERATION-<N>.md file" unless number
        raise Error, "#{file} does not exist" unless File.file?(file)

        @context.agent.plan(prompt(file, number))
      end

      private

      def prompt(file, number)
        folder = File.dirname(file)
        plan_file = File.join(folder, format('PLAN-%03d.md', number.to_i))
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          iteration_file: file, folder:, plans_dir: File.dirname(folder), plan_file:,
          toc_file: TableOfContent.path(folder),
          table_of_content: TableOfContent.section(folder, update: true)
        )
      end
    end
  end
end
