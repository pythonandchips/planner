# frozen_string_literal: true

module Planner
  # An error the user should see. The CLI prints it as "[planner] <message>".
  class Error < StandardError; end

  # Bad command-line usage. The CLI prints the usage text.
  class UsageError < Error; end
end
