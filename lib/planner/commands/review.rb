# frozen_string_literal: true

module Planner
  module Commands
    # Renders the review prompt for a plan or findings file and hands it to the agent.
    class Review
      PLAN_TEMPLATE = File.expand_path('../prompts/review.md.erb', __dir__)
      FINDINGS_TEMPLATE = File.expand_path('../prompts/review_findings.md.erb', __dir__)
      # The files that can be reviewed. The plan number is in group 1, the findings number in group 2.
      SOURCE_NAME = /\A(?:PLAN-(\d+)|FINDINGS-(\d+)(?:-[a-z]+)?)\.md\z/

      KINDS = 'PLAN-<N>.md or FINDINGS-<N>.md'

      def initialize(context)
        @context = context
      end

      def call(args)
        model, lens = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = LatestFile.resolve(args.first, SOURCE_NAME, KINDS)
        match = source_match(file)
        template = match[1] ? PLAN_TEMPLATE : FINDINGS_TEMPLATE
        run_review(file, match[1] || match[2], template, model, read_lens(lens))
      end

      private

      def source_match(file)
        match = File.basename(file).match(SOURCE_NAME)
        raise Error, "#{file} is not a #{KINDS} file" unless match
        raise Error, "#{file} does not exist" unless File.file?(file)

        match
      end

      def run_review(file, number, template, model, lens)
        review_file = review_file(file, number)
        toc_file = TableOfContent.path(File.dirname(file))
        @context.agent.review(prompt(template, file, review_file, lens), model:, report_file: review_file,
                                                                         source_file: file, toc_file:)
      end

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

      def prompt(template, file, review_file, lens)
        title = "#{File.basename(review_file, '.md')} — #{file}"
        folder = File.dirname(file)
        ERB.new(File.read(template), trim_mode: '-').result_with_hash(
          source_file: file, review_file:, lens:, title:, toc_file: TableOfContent.path(folder),
          table_of_content: TableOfContent.section(folder, update: true)
        )
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
