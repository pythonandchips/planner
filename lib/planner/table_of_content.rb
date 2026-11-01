# frozen_string_literal: true

module Planner
  # The TABLE_OF_CONTENT.md a plan folder can have, and the prompt section describing it.
  module TableOfContent
    FILE = 'TABLE_OF_CONTENT.md'
    TEMPLATE = File.expand_path('prompts/_table_of_content.md.erb', __dir__)

    def self.path(folder) = File.join(folder, FILE)

    # The format, preceded by the update rules when update is true.
    def self.section(folder, update:)
      ERB.new(File.read(TEMPLATE), trim_mode: '-')
         .result_with_hash(folder:, toc_file: path(folder), name: File.basename(folder), update:)
    end
  end
end
