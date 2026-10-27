# frozen_string_literal: true

module Planner
  module Commands
    # Hands a plan file to the agent to implement.
    class Run
      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        raise Error, "#{file} does not exist" unless File.file?(file)

        prompt = File.read(file).sub(/\n+\z/, '')
        @context.agent.run(prompt, model:)
      end

      private

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
