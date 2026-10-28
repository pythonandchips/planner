# frozen_string_literal: true

module Planner
  module Commands
    class Skills
      # Prints each skill planner ships, with its description.
      class List
        def initialize(context)
          @context = context
        end

        def call(args)
          raise UsageError unless args.empty?

          skills = SkillCatalog.all(@context.skills_dir)
          return @context.stdout.puts('No skills available.') if skills.empty?

          print_skills(skills)
        end

        private

        def print_skills(skills)
          width = skills.map { |skill| skill.slug.length }.max
          skills.each { |skill| @context.stdout.puts "#{skill.slug.ljust(width)}  #{skill.description}".rstrip }
        end
      end
    end
  end
end
