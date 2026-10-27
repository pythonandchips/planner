# frozen_string_literal: true

module Planner
  module Commands
    # Creates a plan folder under docs/plans and prints its path.
    class New
      def initialize(context)
        @context = context
      end

      def call(args)
        name = args.first
        raise UsageError if name.nil? || name.empty?

        dir = plan_dir(name)
        raise Error, "#{dir} already exists" if dir.directory?

        FileUtils.mkdir_p(dir)
        @context.stdout.puts dir.relative_path_from(@context.root)
      end

      private

      def plan_dir(name)
        slug = Slug.call(name)
        raise Error, "'#{name}' does not contain any usable characters" if slug.empty?

        stamp = @context.clock.call.strftime('%Y%m%d%H%M')
        @context.root / 'docs/plans' / "#{stamp}-#{slug}"
      end
    end
  end
end
