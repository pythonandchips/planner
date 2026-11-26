# frozen_string_literal: true

module Planner
  # Logic for iteration files, ITERATION-<NNN>.md.
  module Iteration
    # The path of the next ITERATION-<NNN>.md in a plan folder: one past the highest ITERATION-NNN.md there,
    # or 001 when there is none. Only regular files named exactly ITERATION-<three digits>.md count.
    module Next
      NAME = /\AITERATION-(\d{3})\.md\z/

      def self.path(folder)
        names = Dir.children(folder).select { |name| File.file?(File.join(folder, name)) }
        numbers = names.filter_map { |name| name[NAME, 1]&.to_i }
        File.join(folder, format('ITERATION-%03d.md', (numbers.max || 0) + 1))
      end
    end
  end
end
