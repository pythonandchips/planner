# frozen_string_literal: true

module Planner
  # Wrappers round outside command-line tools that are not coding agents.
  module Tools
    # Runs the gh CLI and parses its JSON output.
    class Gh
      NOT_INSTALLED = 'gh is not installed; see https://cli.github.com'

      def initialize(runner: Open3.method(:capture3))
        @runner = runner
      end

      def json(*args)
        out, err, status = @runner.call('gh', *args)
        raise Error, "gh failed: #{err.strip}" unless status.success?

        JSON.parse(out)
      rescue Errno::ENOENT
        raise Error, NOT_INSTALLED
      end
    end
  end
end
