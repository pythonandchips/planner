# frozen_string_literal: true

module Planner
  module Commands
    # Renders the toc prompt for a plan folder and hands it to the agent.
    class Toc
      TEMPLATE = File.expand_path('../prompts/toc.md.erb', __dir__)

      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        folder = args.first.chomp('/')
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        toc_file = TableOfContent.path(folder)
        @context.agent.toc(prompt(folder, toc_file), model:, toc_file:)
      end

      private

      def prompt(folder, toc_file)
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          folder:, toc_file:, table_of_content: TableOfContent.section(folder, update: false)
        )
      end

      # Removes the options from args and returns the chosen model.
      def parse(args)
        model = @context.agent.default_toc_model
        OptionParser.new { |opts| opts.on('-m', '--model MODEL') { |value| model = value } }.parse!(args)
        model
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
