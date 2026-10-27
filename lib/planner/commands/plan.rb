# frozen_string_literal: true

module Planner
  module Commands
    # Hands an iteration file to the agent to be turned into a plan file.
    class Plan
      def initialize(context)
        @context = context
      end

      def call(args)
        file = args.first
        raise UsageError if file.nil? || file.empty?
        raise Error, "#{file} does not exist" unless File.file?(file)

        @context.agent.plan(file)
      end
    end
  end
end
