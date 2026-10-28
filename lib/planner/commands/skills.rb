# frozen_string_literal: true

module Planner
  module Commands
    # Dispatches `planner skills <subcommand>` and shows the skills usage on bad usage.
    class Skills
      SUBCOMMANDS = {
        'list' => Skills::List,
        'install' => Skills::Install
      }.freeze

      USAGE = <<~TEXT
        usage: planner skills list
               planner skills install [--global] [--only <slug>,...]
      TEXT

      def initialize(context)
        @context = context
      end

      def call(args)
        subcommand = SUBCOMMANDS[args.first] or raise UsageError, USAGE
        subcommand.new(@context).call(args.drop(1))
      rescue UsageError
        raise UsageError, USAGE
      end
    end
  end
end
