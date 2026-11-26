# frozen_string_literal: true

module Planner
  module Commands
    # Creates the next empty ITERATION-<NNN>.md in a plan folder, numbered one past the highest
    # ITERATION-NNN.md there, and prints the file's path.
    class Next
      def initialize(context)
        @context = context
      end

      def call(args)
        raise UsageError if args.size != 1 || args.first.start_with?('-')

        folder = args.first.chomp('/')
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        path = Iteration::Next.path(folder)
        File.write(path, '')
        @context.stdout.puts path
      end
    end
  end
end
