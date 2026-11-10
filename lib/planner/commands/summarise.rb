# frozen_string_literal: true

module Planner
  module Commands
    # Renders the summarise prompt for a plan, review or findings file and hands it to the agent.
    class Summarise
      TEMPLATE = File.expand_path('../prompts/summarise.md.erb', __dir__)
      # The files that can be summarised. The number is in whichever group matched.
      SOURCE_NAME = /\A(?:PLAN-(\d+)|(?:REVIEW|FINDINGS)-(\d+)(?:-[a-z]+)?)\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        model, brief = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        number = source_number(file)
        raise Error, "#{file} does not exist" unless File.file?(file)

        run_summarise(file, number, model, read_brief(brief))
      end

      private

      def source_number(file)
        number = File.basename(file).match(SOURCE_NAME)&.captures&.find(&:itself)
        raise Error, "#{file} is not a PLAN-<N>.md, REVIEW-<N>.md or FINDINGS-<N>.md file" unless number

        number
      end

      def run_summarise(file, number, model, brief)
        summary_base = summary_base(file, number)
        toc_file = TableOfContent.path(File.dirname(file))
        @context.agent.summarise(prompt(file, summary_base, model, brief), model:, summary_base:, toc_file:)
      end

      # SUMMARY-<NNN>, or the first free SUMMARY-<NNN>-a, -b ... -z, -aa ... after it. A base is taken when
      # a file <base>.<ext> or a folder <base> exists.
      def summary_base(file, number)
        base = File.join(File.dirname(file), format('SUMMARY-%03d', number.to_i))
        path = base
        suffix = 'a'
        while taken?(path)
          path = "#{base}-#{suffix}"
          suffix = suffix.succ
        end
        path
      end

      def taken?(base) = File.exist?(base) || Dir.glob("#{base}.*").any?

      # Reads stdin for "-", and returns nil for no brief or a blank one.
      def read_brief(brief)
        brief = @context.stdin.read if brief == '-'
        brief = brief&.strip
        brief unless brief.nil? || brief.empty?
      end

      def prompt(file, summary_base, model, brief)
        folder = File.dirname(file)
        ERB.new(File.read(TEMPLATE), trim_mode: '-').result_with_hash(
          source_file: file, folder:, summary_base:, model:, brief:, toc_file: TableOfContent.path(folder),
          table_of_content: TableOfContent.section(folder, update: true)
        )
      end

      # Removes the options from args and returns the chosen model and the raw brief.
      def parse(args)
        model = @context.agent.default_summarise_model
        brief = nil
        OptionParser.new do |opts|
          opts.on('-m', '--model MODEL') { |value| model = value }
          opts.on('-b', '--brief BRIEF') { |value| brief = value }
        end.parse!(args)
        [model, brief]
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
