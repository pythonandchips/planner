# frozen_string_literal: true

module Planner
  module Commands
    # Wraps a plan file in the run prompt and hands it to the agent to implement.
    class Run
      TEMPLATE = File.expand_path('../prompts/run.md.erb', __dir__)

      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        raise Error, "#{file} does not exist" unless File.file?(file)

        @context.agent.run(prompt(file, model), model:)
      end

      private

      def prompt(file, model)
        plan = File.read(file).sub(/\n+\z/, '')
        ERB.new(File.read(TEMPLATE)).result_with_hash(plan_file: file, plan:, model:)
      end

      # Removes the options from args and returns the chosen model.
      def parse(args)
        model = @context.agent.default_run_model
        OptionParser.new { |opts| opts.on('-m', '--model MODEL') { |value| model = value } }.parse!(args)
        model
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
