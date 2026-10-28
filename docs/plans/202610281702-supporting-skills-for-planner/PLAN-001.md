# PLAN-001 — Add a `planner skills` command

Add `planner skills list` and `planner skills install [--global] [--only <slug>,...]`. The
canonical skills live in the planner repo under `lib/planner/skills/<slug>/` and ship in the
gem. `list` prints each skill's slug and description. `install` copies skills into
`.claude/skills` under the current directory, or into `~/.claude/skills` with `--global`.
When an installed skill would be replaced by a different version, it lists them and asks for
confirmation first. `skills` is a top-level command with its own small registry of
subcommands, so later ones (for example `uninstall`) slot in the same way. This plan ships the
mechanism only, with no skills. Also in scope: `home` and `skills_dir` on `Context`, a
usage text on `UsageError`, the gemspec, specs, the README, the glossary and the TODO.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Command shape | Nested subcommands: `planner skills list` and `planner skills install [--global] [--only <slug>,...]`. `Commands::Skills` dispatches through its own `SUBCOMMANDS` registry. |
| Where canonical skills live | `lib/planner/skills/<slug>/`. The gemspec ships `lib/planner/skills/**/*`. |
| What is a skill | A folder under the skills dir that contains `SKILL.md`. The whole folder is the skill. |
| Skills shipped in this plan | None. Mechanism only. Specs use fixture skills. |
| Local destination | `.claude/skills` under `Context#root` (the current directory) |
| Global destination | `--global` installs to `<home>/.claude/skills` |
| Home directory | A new `home` member on `Context`. `exe/planner` passes `Pathname(Dir.home)`. Specs pass a tmp dir. |
| Skills directory | A new `skills_dir` member on `Context`. `exe/planner` passes `Planner::SkillCatalog::DIR`. Specs pass a fixture dir. |
| Destination shown in output | `.claude/skills/...` for local, `~/.claude/skills/...` for global |
| Missing destination folder | Created (`mkdir_p`) |
| Overwriting a skill | Replace the whole folder: `rm_rf` the existing one, then `cp_r` the gem's |
| Identical installed skill | Same relative file list and same bytes in every file. Not a conflict, not in the confirmation, not rewritten. Printed as `unchanged <slug>`. |
| Confirmation | Only when at least one selected skill exists at the destination and differs. Printed to `Context#stdout`, answer read with `Context#stdin.gets`. |
| Confirmation text | `These skills already exist in <dest> and will be replaced:`, one `  <slug>` line each, then `Overwrite? [y/N] ` with no newline |
| Accepted answers | `y` or `yes`, case-insensitive, surrounding whitespace ignored. Anything else, including an empty line or EOF, declines. |
| `--yes` / `--force` flag | None |
| User declines | Install nothing. `Error, 'Install cancelled'` (`[planner] Install cancelled`, exit 1). |
| `--only` forms | `--only a,b` and `--only=a,b`. Repeated `--only` flags accumulate. |
| Unknown `--only` slug | `Error, "Unknown skill: <a>, <b>"` naming every unknown slug in the given order, before any prompt or file change |
| `list` output | One line per skill, sorted by slug: slug left-justified to the longest slug, two spaces, description. Trailing whitespace stripped. |
| `list` options | None. Any argument is a usage error. |
| `install` output | One line per selected skill, sorted by slug: `installed <slug> -> <dest>/<slug>` or `unchanged <slug>` |
| No skills available | `list` and `install` both print `No skills available.` and exit 0. `install` changes nothing. This check runs before `--only` validation. |
| Description source | `description` in the `SKILL.md` YAML frontmatter, read with `YAML.safe_load`. Missing frontmatter, YAML that fails to load (broken, or using a class or alias `safe_load` rejects, such as a date) or no `description` gives a blank description. |
| Shipped skill format | Spec-enforced: every skill in `lib/planner/skills` has frontmatter `name` equal to its folder name and a non-empty `description` |
| Usage | Top-level `USAGE` gains `planner skills <list\|install> ...`. Skills has its own usage block. A missing or unknown subcommand, an extra argument or a bad flag under `skills` prints the skills block to stderr and exits 1. |
| How the skills usage reaches the CLI | `UsageError` takes an optional usage text. The CLI prints it, or `USAGE` when there is none. |
| Docs | README (through `update-readme`), a glossary **skill** entry, and a TODO bullet for shipping the first skills |

## Files to create / change

```
lib/planner/skill_catalog.rb             new: SkillCatalog (DIR, Skill, .all)
lib/planner/commands/skills.rb           new: Commands::Skills (dispatcher + USAGE)
lib/planner/commands/skills/list.rb      new: Commands::Skills::List
lib/planner/commands/skills/install.rb   new: Commands::Skills::Install
lib/planner/errors.rb                    UsageError takes an optional usage text
lib/planner/context.rb                   add home and skills_dir
lib/planner/cli.rb                       register 'skills', add the usage line, print e.usage
lib/planner.rb                           require yaml and the new files
exe/planner                              pass home: and skills_dir:
planner.gemspec                          ship lib/planner/skills/**/*
spec/planner/skill_catalog_spec.rb       new
spec/planner/commands/skills_spec.rb     new: dispatcher, list and install
spec/planner/cli_spec.rb                 home:/skills_dir: in Context.new, skills usage example
spec/planner/commands/new_spec.rb        home:/skills_dir: in Context.new
spec/planner/commands/plan_spec.rb       home:/skills_dir: in Context.new
spec/planner/commands/run_spec.rb        home:/skills_dir: in Context.new
spec/planner/commands/review_spec.rb     home:/skills_dir: in Context.new
spec/exe/planner_spec.rb                 skills list smoke example
README.md                                planner skills usage lines
docs/GLOSSARY.md                         skill entry
docs/TODO.md                             first-skills bullet
```

Do not create `lib/planner/skills/`. Git can't track an empty folder, and the code handles it
being missing.

## Implementation

### `lib/planner/errors.rb`

Keep `Error` as it is. Change `UsageError`:

```ruby
# Bad command-line usage. The CLI prints the usage text: the one given, or its own.
class UsageError < Error
  attr_reader :usage

  def initialize(usage = nil)
    @usage = usage
    super('bad usage')
  end
end
```

`raise UsageError` with no argument keeps working.

### `lib/planner/context.rb`

`Context = Data.define(:root, :home, :skills_dir, :agent, :stdin, :stdout, :clock)`. Keep the
comment.

### `lib/planner/skill_catalog.rb`

```ruby
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
```

`Psych::Exception` covers `Psych::SyntaxError` as well as `Psych::DisallowedClass` (a date,
for example) and `Psych::AliasesNotEnabled`. Rescuing only `Psych::SyntaxError` would let those
crash `list` and `install`.

### `lib/planner/commands/skills.rb`

```ruby
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
```

`Skills::List` and `Skills::Install` live in their own files, which open `class Skills` with
no superclass. `lib/planner.rb` requires them before this file so `SUBCOMMANDS` can name them.

### `lib/planner/commands/skills/list.rb`

```ruby
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

          width = skills.map { |skill| skill.slug.length }.max
          skills.each { |skill| @context.stdout.puts "#{skill.slug.ljust(width)}  #{skill.description}".rstrip }
        end
      end
    end
  end
end
```

### `lib/planner/commands/skills/install.rb`

```ruby
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

          skills = choose(skills, only)
          dest, shown = destination(global)
          unchanged, changed = skills.partition { |skill| identical?(skill.path, dest / skill.slug) }
          confirm(changed.select { |skill| (dest / skill.slug).exist? }, shown)
          install(skills, unchanged, dest, shown)
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

        def install(skills, unchanged, dest, shown)
          FileUtils.mkdir_p(dest)
          skills.each do |skill|
            next @context.stdout.puts("unchanged #{skill.slug}") if unchanged.include?(skill)

            FileUtils.rm_rf(dest / skill.slug)
            FileUtils.cp_r(skill.path, dest / skill.slug)
            @context.stdout.puts "installed #{skill.slug} -> #{shown}/#{skill.slug}"
          end
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
```

- A destination path that exists but is a file (not a folder) counts as a conflict and is
  replaced like any other.
- If RuboCop objects (for example `Metrics/MethodLength`, `Metrics/AbcSize` or line length),
  reshape the code to satisfy it. The behaviour above must stay the same.

### `lib/planner/cli.rb`

- Add `'skills' => Commands::Skills` to `COMMANDS`, after `'review'`.
- Add a line to `USAGE` after the `review` line, aligned with it:
  `       planner skills <list|install> ...`
- Change the usage rescue to:

```ruby
rescue UsageError => e
  @stderr.print e.usage || USAGE
  1
```

### `lib/planner.rb`

- Add `require 'yaml'` with the other stdlib requires, in alphabetical order (after
  `pathname`).
- Add `require_relative 'planner/skill_catalog'` after `planner/slug`.
- After the `review` require, add in this order:
  `planner/commands/skills/list`, `planner/commands/skills/install`, `planner/commands/skills`.

### `exe/planner`

`Context.new` gets `home: Pathname(Dir.home),` and `skills_dir: Planner::SkillCatalog::DIR,`
after `root:`.

### `planner.gemspec`

```ruby
spec.files = Dir['lib/**/*.rb', 'lib/**/*.erb', 'lib/planner/skills/**/*', 'exe/*', 'README.md']
               .select { |path| File.file?(path) }
```

### Specs

- Add `home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',` after `root:` (or
  `root:,`) to every existing `Planner::Context.new` in `cli_spec.rb`, `new_spec.rb`,
  `plan_spec.rb`, `run_spec.rb` and `review_spec.rb`. Change nothing else in those files
  except the new `cli_spec` example below.
- `spec/planner/cli_spec.rb`: add "prints the skills usage and returns 1 for a bad skills
  subcommand": `cli.call(%w[skills bogus])` returns 1 and `stderr.string` equals
  `Planner::Commands::Skills::USAGE`.
- `spec/exe/planner_spec.rb`: add "lists no skills while none ship": `planner('skills',
  'list')` exits 0 with output `"No skills available.\n"`. This holds as long as
  `lib/planner/skills` is empty; when the first skill ships, that iteration updates the
  example.
- `spec/planner/skill_catalog_spec.rb` (`:aggregate_failures`, in the tmp dir):
  - `.all` on a missing dir returns `[]`.
  - With fixture folders `b/SKILL.md` (frontmatter `name: b`, `description: Bee`),
    `a/SKILL.md` (frontmatter with `description: Ay`, plus `a/scripts/x.sh`), `c/` with no
    `SKILL.md`, and a plain file `notes.md`: slugs are `%w[a b]`, descriptions
    `%w[Ay Bee]`, and `path` is the folder.
  - `SKILL.md` with no frontmatter, with broken YAML (`description: [`), with a value
    `safe_load` rejects (`description: Dated` plus `created: 2026-01-01`), and with
    frontmatter that has no `description` each give `''`.
  - "every shipped skill names itself and has a description": for each skill in
    `SkillCatalog.all(SkillCatalog::DIR)`, the frontmatter `name` equals the slug and
    `description` is not blank. It passes with zero skills.
- `spec/planner/commands/skills_spec.rb` (`:aggregate_failures`, in the tmp dir). Build a
  context with `root: Pathname.pwd`, `home: Pathname.pwd / 'home'`,
  `skills_dir: Pathname.pwd / 'skills'`, `stdin` from `let(:stdin) { StringIO.new }`, and
  `stdout` from `let(:stdout) { StringIO.new }`. Call `described_class.new(context).call(args)`
  on `Planner::Commands::Skills`. Write a helper that creates a fixture skill:
  `skills/<slug>/SKILL.md` with frontmatter `name: <slug>` and `description: <text>`, plus
  any extra files. Examples:
  - Dispatcher: no args, `bogus`, `list extra`, `install --bogus` and `install extra` each
    raise `Planner::UsageError` whose `usage` is `described_class::USAGE`.
  - List with no skills dir prints `"No skills available.\n"`.
  - List with skills `git-commit` ("How to write commits") and `yarn` ("Run yarn") prints
    `"git-commit  How to write commits\nyarn        Run yarn\n"`. A skill with a blank
    description prints just its slug with no trailing spaces.
  - Install with no skills prints `"No skills available.\n"`, creates no `.claude`, and
    `--only nope` with no skills prints the same message rather than an error.
  - Install with two skills into an empty project: creates `.claude/skills/<slug>/` copies
    with the same files (including a nested `scripts/x.sh`), prints
    `"installed git-commit -> .claude/skills/git-commit\ninstalled yarn -> .claude/skills/yarn\n"`,
    and prints no prompt.
  - `--global` installs into `home/.claude/skills/` (nothing under `./.claude`) and prints
    `~/.claude/skills/<slug>` paths.
  - `--only yarn`, `--only=yarn` and `--only git-commit --only yarn` select the right
    skills. `--only yarn,nope,zzz` raises `Planner::Error, 'Unknown skill: nope, zzz'` and
    creates nothing.
  - An identical installed copy: no prompt, prints `unchanged <slug>`, files untouched
    (an mtime check or a marker that would be lost on rewrite is fine).
  - A changed installed copy (different content, or an extra file in the installed folder),
    with `stdin` `"y\n"`: stdout starts with
    `"These skills already exist in .claude/skills and will be replaced:\n  git-commit\nOverwrite? [y/N] "`,
    the folder now matches the source exactly (the extra file is gone), and the
    `installed` line follows. `"YES\n"` and `" yes \n"` also confirm.
  - With `stdin` `"n\n"`, `"\n"` and empty (EOF): raises `Planner::Error, 'Install cancelled'`
    and neither the conflicting skill nor a new skill in the same run is written.
  - The prompt lists only changed existing skills, not new or identical ones.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. Add after the
`planner review` line:

```
- `planner skills list`: list the skills planner ships.
- `planner skills install [--global] [--only <slug>,...]`: copy the skills into `.claude/skills`, or `~/.claude/skills` with `--global`; asks before replacing a skill that has changed.
```

### `docs/GLOSSARY.md`

Add before the **agent** entry:

```
- **skill**: A folder under `lib/planner/skills/<slug>/` with a `SKILL.md`, for the agent to use. Copied into `.claude/skills` by `planner skills install`.
```

### `docs/TODO.md`

Append:

```
- Ship the first skills under `lib/planner/skills` (for example writing git commits, running yarn commands).
```

## Verification

1. `bundle exec rake` passes: all specs, including the new and updated ones, plus RuboCop with
   no offences.
2. `bundle exec rake install` succeeds. Then, from a scratch folder outside the repo:
   - `planner` prints the usage text including `planner skills <list|install> ...`, exit 1.
   - `planner skills` and `planner skills bogus` print the skills usage block, exit 1.
   - `planner skills list` and `planner skills install` each print `No skills available.`,
     exit 0, and no `.claude` folder appears.
3. Manual end-to-end with a temporary skill (do not commit it): create
   `lib/planner/skills/demo/SKILL.md` with frontmatter `name: demo` and
   `description: Demo skill`, run `bundle exec rake install`, then in a scratch folder:
   - `planner skills list` prints `demo  Demo skill`.
   - `planner skills install` prints `installed demo -> .claude/skills/demo`.
   - Running it again prints `unchanged demo`.
   - Edit `.claude/skills/demo/SKILL.md`, then run `printf 'n\n' | planner skills install`:
     it prints the confirmation, then `[planner] Install cancelled`, exit 1, and the edit
     survives. Then run `printf 'y\n' | planner skills install`: it prints
     `installed demo -> .claude/skills/demo` and the file matches the gem's again.
   - `planner skills install --only nope` prints `[planner] Unknown skill: nope`, exit 1.
   - `gem contents planner` lists `lib/planner/skills/demo/SKILL.md`.
   Then delete `lib/planner/skills/` and run `bundle exec rake install` again so the installed
   gem matches the commit. Do not run `--global` in this check; it is a manual check for the
   user.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes, and the temporary `demo` skill is gone. Run each git command as its own Bash call:

```
git add lib exe spec planner.gemspec README.md docs/GLOSSARY.md docs/TODO.md docs/plans/202610281702-supporting-skills-for-planner/ITERATION-001.md docs/plans/202610281702-supporting-skills-for-planner/PLAN-001.md
```

Stage only this folder's `ITERATION-001.md` and `PLAN-001.md`. Do not stage any `REVIEW-*.md`
file in the folder. Write the message to a file and commit:

```
git commit -F <file>
```

Suggested message:

```
Add planner skills list and install

Ship skills with the gem under lib/planner/skills and add
`planner skills list` to show them and `planner skills install` to
copy them into .claude/skills, or ~/.claude/skills with --global.
--only limits which skills are installed. Replacing a skill that has
changed asks for confirmation first; identical skills are left alone.
```
