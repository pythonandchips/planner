# frozen_string_literal: true

module Planner
  # Turns a given name into a folder-safe slug.
  module Slug
    def self.call(name)
      name.tr('A-Z', 'a-z').gsub(/[^a-z0-9]+/, '-').delete_prefix('-').delete_suffix('-')
    end
  end
end
