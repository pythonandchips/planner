# frozen_string_literal: true

module Planner
  module Commands
    # Wraps a plan file in the run prompt and hands it to the agent to implement, or prints it as JSON.
    class Run
      TEMPLATE = File.expand_path('../prompts/run.md.erb', __dir__)

      def initialize(context)
        @context = context
      end

      def call(args)
        model, print_only = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        raise Error, "#{file} does not exist" unless File.file?(file)

        text = prompt(file, model)
        return print_json(text, model) if print_only

        @context.agent.run(text, model:)
      end

      private

      def print_json(text, model)
        @context.stdout.puts JSON.pretty_generate(prompt: text, model:, allowedTools: @context.agent.run_tools)
      end

      def prompt(file, model)
        plan = File.read(file).sub(/\n+\z/, '')
        folder = File.dirname(file)
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          plan_file: file, plan:, model:, toc_file: TableOfContent.path(folder),
          table_of_content: TableOfContent.section(folder, update: true)
        )
      end

      # Removes the options from args and returns the chosen model and whether to print instead of run.
      def parse(args)
        model = @context.agent.default_run_model
        print_only = false
        OptionParser.new do |opts|
          opts.on('-m', '--model MODEL') { |value| model = value }
          opts.on('-p', '--print') { print_only = true }
        end.parse!(args)
        [model, print_only]
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
