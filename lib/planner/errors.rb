# frozen_string_literal: true

module Planner
  # An error the user should see. The CLI prints it as "[planner] <message>".
  class Error < StandardError; end

  # Bad command-line usage. The CLI prints the usage text: the one given, or its own.
  class UsageError < Error
    attr_reader :usage

    def initialize(usage = nil)
      @usage = usage
      super('bad usage')
    end
  end
end
