# frozen_string_literal: true

module Planner
  module Commands
    # Renders the explore prompt for an iteration file and hands it to the agent.
    class Explore
      TEMPLATE = File.expand_path('../prompts/explore.md.erb', __dir__)
      ITERATION_NAME = /\AITERATION-(\d+)\.md\z/
      PARTIALS = %w[findings_structure check_in stats summary_for_user].freeze

      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        number = File.basename(file)[ITERATION_NAME, 1]
        raise Error, "#{file} is not an ITERATION-<N>.md file" unless number
        raise Error, "#{file} does not exist" unless File.file?(file)

        findings_file = findings_file(file, number)
        @context.agent.explore(prompt(file, findings_file, model), model:, findings_file:, toc_file: toc_file(file))
      end

      private

      def toc_file(file) = TableOfContent.path(File.dirname(file))

      # FINDINGS-<NNN>.md, or the first free FINDINGS-<NNN>-a.md, -b ... -z, -aa ... after it.
      def findings_file(file, number)
        base = File.join(File.dirname(file), format('FINDINGS-%03d', number.to_i))
        path = "#{base}.md"
        suffix = 'a'
        while File.exist?(path)
          path = "#{base}-#{suffix}.md"
          suffix = suffix.succ
        end
        path
      end

      def prompt(file, findings_file, model)
        folder = File.dirname(file)
        locals = { findings_file:, model:, title: File.basename(findings_file, '.md') }
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          iteration_file: file, folder:, toc_file: TableOfContent.path(folder),
          table_of_content: TableOfContent.section(folder, update: true), **locals, **partials(locals)
        )
      end

      # Each _explore_<name>.md.erb partial rendered with locals, without its trailing newline, keyed by name.
      def partials(locals)
        PARTIALS.to_h do |name|
          path = File.expand_path("../prompts/_explore_#{name}.md.erb", __dir__)
          [name.to_sym, ERB.new(File.read(path)).result_with_hash(locals).chomp]
        end
      end

      # Removes the options from args and returns the chosen model.
      def parse(args)
        model = @context.agent.default_explore_model
        OptionParser.new { |opts| opts.on('-m', '--model MODEL') { |value| model = value } }.parse!(args)
        model
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
