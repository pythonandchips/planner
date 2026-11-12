# frozen_string_literal: true

module Planner
  module Commands
    # Creates a plan folder under docs/plans, or the folder given with --dir, and prints its path.
    class New
      DEFAULT_DIR = 'docs/plans'

      def initialize(context)
        @context = context
      end

      def call(args)
        dir = parse(args)
        raise UsageError if dir.empty?

        name = args.first
        raise UsageError if name.nil? || name.empty?

        folder = plan_folder(dir, name)
        path = @context.root / folder
        raise Error, "#{path} already exists" if path.directory?

        FileUtils.mkdir_p(path)
        @context.stdout.puts folder
      end

      private

      # Removes the options from args and returns the chosen folder.
      def parse(args)
        dir = DEFAULT_DIR
        OptionParser.new do |opts|
          opts.on('-d', '--dir DIR') { |value| dir = value }
        end.parse!(args)
        dir
      rescue OptionParser::ParseError
        raise UsageError
      end

      def plan_folder(dir, name)
        slug = Slug.call(name)
        raise Error, "'#{name}' does not contain any usable characters" if slug.empty?

        stamp = @context.clock.call.strftime('%Y%m%d%H%M')
        Pathname(dir) / "#{stamp}-#{slug}"
      end
    end
  end
end
