# frozen_string_literal: true

module Planner
  module Commands
    # Renders the review prompt for a plan file and hands it to the agent.
    class Review
      TEMPLATE = File.expand_path('../prompts/review.md.erb', __dir__)
      PLAN_NAME = /\APLAN-(\d+)\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        model, lens = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        number = File.basename(file)[PLAN_NAME, 1]
        raise Error, "#{file} is not a PLAN-<N>.md file" unless number
        raise Error, "#{file} does not exist" unless File.file?(file)

        review_file = review_file(file, number)
        @context.agent.review(prompt(file, review_file, read_lens(lens)),
                              model:, report_file: review_file, plan_file: file)
      end

      private

      # REVIEW-<NNN>.md, or the first free REVIEW-<NNN>-a.md, -b ... -z, -aa ... after it.
      def review_file(file, number)
        base = File.join(File.dirname(file), format('REVIEW-%03d', number.to_i))
        path = "#{base}.md"
        suffix = 'a'
        while File.exist?(path)
          path = "#{base}-#{suffix}.md"
          suffix = suffix.succ
        end
        path
      end

      # Reads stdin for "-", and returns nil for no lens or a blank one.
      def read_lens(lens)
        lens = @context.stdin.read if lens == '-'
        lens = lens&.strip
        lens unless lens.nil? || lens.empty?
      end

      def prompt(file, review_file, lens)
        title = "#{File.basename(review_file, '.md')} — #{file}"
        ERB.new(File.read(TEMPLATE), trim_mode: '-')
           .result_with_hash(plan_file: file, review_file:, lens:, title:)
      end

      # Removes the options from args and returns the chosen model and the raw lens.
      def parse(args)
        model = @context.agent.default_review_model
        lens = nil
        OptionParser.new do |opts|
          opts.on('-m', '--model MODEL') { |value| model = value }
          opts.on('-l', '--lens LENS') { |value| lens = value }
        end.parse!(args)
        [model, lens]
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
