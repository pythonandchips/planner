# frozen_string_literal: true

module Planner
  # The skills planner ships: each folder under DIR that holds a SKILL.md.
  module SkillCatalog
    DIR = Pathname(File.expand_path('skills', __dir__))
    FRONTMATTER = /\A---\n(.*?)\n---\n/m

    Skill = Data.define(:slug, :path, :description)

    # Skills in dir, sorted by slug. Empty when dir is missing.
    def self.all(dir)
      return [] unless dir.directory?

      dir.children.select { |path| (path / 'SKILL.md').file? }.sort.map do |path|
        Skill.new(slug: path.basename.to_s, path:, description: frontmatter(path / 'SKILL.md')['description'].to_s)
      end
    end

    # The SKILL.md frontmatter as a hash, or {} when it is missing or YAML.safe_load rejects it.
    def self.frontmatter(file)
      match = File.read(file).match(FRONTMATTER) or return {}
      data = YAML.safe_load(match[1])
      data.is_a?(Hash) ? data : {}
    rescue Psych::Exception
      {}
    end
  end
end
