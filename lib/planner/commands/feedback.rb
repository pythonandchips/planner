# frozen_string_literal: true

module Planner
  module Commands
    # Writes a pull request's open review comments to the next ITERATION-<NNN>.md in a plan folder, prints
    # its path, then plans it as `planner plan` does.
    class Feedback
      def initialize(context, gh: Tools::Gh.new)
        @context = context
        @gh = gh
      end

      def call(args)
        raise UsageError if args.size != 2 || args.any? { |arg| arg.start_with?('-') }

        folder = args.first.chomp('/')
        pr = args.last
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        feedback = Planner::Feedback::PullRequest.fetch(@gh, pr)
        raise Error, "#{pr} has no review comments" if feedback.empty?

        path = Iteration::Next.path(folder)
        File.write(path, feedback.to_markdown)
        @context.stdout.puts path
        Plan.new(@context).call([path])
      end
    end
  end
end
