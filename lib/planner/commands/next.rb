# frozen_string_literal: true

module Planner
  module Commands
    # Creates the next empty ITERATION-<NNN>.md in a plan folder, numbered one past the highest
    # ITERATION-NNN.md there, and prints the file's path.
    class Next
      ITERATION = /\AITERATION-(\d{3})\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        raise UsageError if args.size != 1 || args.first.start_with?('-')

        folder = args.first.chomp('/')
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        path = File.join(folder, format('ITERATION-%03d.md', next_number(folder)))
        File.write(path, '')
        @context.stdout.puts path
      end

      private

      def next_number(folder)
        names = Dir.children(folder).select { |name| File.file?(File.join(folder, name)) }
        numbers = names.filter_map { |name| name[ITERATION, 1]&.to_i }
        (numbers.max || 0) + 1
      end
    end
  end
end
