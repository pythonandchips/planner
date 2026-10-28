# frozen_string_literal: true

module Planner
  module Commands
    class Skills
      # Copies skills into .claude/skills, asking before it replaces a changed one.
      class Install
        def initialize(context)
          @context = context
        end

        def call(args)
          global, only = parse(args)
          raise UsageError unless args.empty?

          skills = SkillCatalog.all(@context.skills_dir)
          return @context.stdout.puts('No skills available.') if skills.empty?

          install(choose(skills, only), *destination(global))
        end

        private

        # Removes the options from args and returns [global, only]. only is nil without --only.
        def parse(args)
          global = false
          only = nil
          OptionParser.new do |opts|
            opts.on('--global') { global = true }
            opts.on('--only SLUGS', Array) { |slugs| only = (only || []) + slugs }
          end.parse!(args)
          [global, only]
        rescue OptionParser::ParseError
          raise UsageError
        end

        def choose(skills, only)
          return skills unless only

          unknown = only - skills.map(&:slug)
          raise Error, "Unknown skill: #{unknown.join(', ')}" unless unknown.empty?

          skills.select { |skill| only.include?(skill.slug) }
        end

        # The folder to install into, and how to show it.
        def destination(global)
          return [@context.home / '.claude/skills', '~/.claude/skills'] if global

          [@context.root / '.claude/skills', '.claude/skills']
        end

        def confirm(conflicts, shown)
          return if conflicts.empty?

          @context.stdout.puts "These skills already exist in #{shown} and will be replaced:"
          conflicts.each { |skill| @context.stdout.puts "  #{skill.slug}" }
          @context.stdout.print 'Overwrite? [y/N] '
          answer = @context.stdin.gets.to_s.strip.downcase
          raise Error, 'Install cancelled' unless %w[y yes].include?(answer)
        end

        def install(skills, dest, shown)
          unchanged, changed = skills.partition { |skill| identical?(skill.path, dest / skill.slug) }
          confirm(changed.select { |skill| (dest / skill.slug).exist? }, shown)
          FileUtils.mkdir_p(dest)
          skills.each { |skill| copy(skill, dest, shown, unchanged.include?(skill)) }
        end

        def copy(skill, dest, shown, unchanged)
          return @context.stdout.puts("unchanged #{skill.slug}") if unchanged

          FileUtils.rm_rf(dest / skill.slug)
          FileUtils.cp_r(skill.path, dest / skill.slug)
          @context.stdout.puts "installed #{skill.slug} -> #{shown}/#{skill.slug}"
        end

        # Same relative file list and the same bytes in every file.
        def identical?(source, target)
          return false unless target.directory?

          files = files(source)
          files == files(target) && files.all? { |file| FileUtils.compare_file(source / file, target / file) }
        end

        def files(dir)
          Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).reject { |file| File.directory?(dir / file) }.sort
        end
      end
    end
  end
end
