# PLAN-001 — Add a `planner review` subcommand

Add `planner review [--model <model>] [--lens <text>|-] <plan-file>`. It has an agent review
a `PLAN-<N>.md` file against the codebase. The agent writes a plain-English report to
`REVIEW-<NNN>.md` in the plan folder, or to `REVIEW-<NNN>-a.md`, `-b` and so on when earlier
reviews exist, and then summarises the review in the session. An optional lens narrows the
review. The lens can be given inline, or piped on stdin with `--lens -` when the context is
large. The review runs in an interactive `claude` session (default model `opus`). Its tools
are limited to Read, Grep, Glob and Write, and only the write to the report file is
auto-approved. The prompt is an ERB template, `lib/planner/prompts/review.md.erb`, built the
same way as the `plan` and `run` prompts. Also in scope: `stdin` on `Context`, specs, the
README and the glossary.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Review file number | Matches the plan number, zero-padded to 3 digits: `PLAN-001.md` → `REVIEW-001.md` (`PLAN-3.md` → `REVIEW-003.md`) |
| Review file already exists | Add a letter suffix. The order is `REVIEW-001.md`, `REVIEW-001-a.md`, `REVIEW-001-b.md` … `-z`, then `-aa`, `-ab` … (Ruby `String#succ`). Planner picks the first free name and tells the agent. |
| File name validation | Name check first: `Error, "<file> is not a PLAN-<N>.md file"`. Then the existence check: `Error, "<file> does not exist"`. Same order as `plan`. |
| Lens on stdin | `--lens -` reads all of stdin. Any other value is the literal lens text. |
| `--lens -` when stdin is a terminal | Read anyway. It waits for typed input until Ctrl-D, as normal on Unix. |
| Empty lens (`--lens ""`, whitespace only, or empty stdin) | Treated as no lens, so the agent does a general review |
| Model | `-m/--model MODEL`, default `opus` (new `default_review_model` on the agent). An empty model is a `UsageError`, as in `run`. |
| Option forms | `-l/--lens LENS` and `-m/--model MODEL` |
| Session | Interactive `claude` session (exec, like `plan` and `run`). The in-session summary appears there. |
| Tool limits | `--tools=Read,Grep,Glob,Write` and `--allowedTools=Edit(<review-file>)`. No Bash. Only the report write is auto-approved. Any other write prompts the user. |
| Agent interface | `review(prompt, model:, report_file:)` and `default_review_model` on `Agents::Claude`, with `FakeAgent` mirroring them |
| How the plan reaches the agent | Path only. The agent reads the file itself. |
| What the reviewer reads | The plan file and the codebase. Not the other files in the plan folder. |
| Focus with no lens | A general review against the fixed five-point checklist in the prompt |
| Focus with a lens | The lens only. The general checklist is left out. |
| Report structure | Fixed headings: `# <title>`, `## Lens` (only when a lens is given), `## Summary`, `## High-confidence findings`, `## Lower-confidence concerns`, `## Top recommendations` |
| Prompt wording | Exactly the template text in Implementation (the user approved the draft) |
| How stdin reaches the command | A new `stdin` member on `Context`. `exe/planner` passes `$stdin`. Specs pass a `StringIO`. |
| Docs | README (through `update-readme`) and a glossary "review file" entry. No TODO change. |
| Spec depth for the prompt | Key content checks, not an exact match |

## Files to create / change

```
lib/planner/prompts/review.md.erb        new: the review prompt template
lib/planner/commands/review.rb           new: Commands::Review
lib/planner/agents/claude.rb             review(prompt, model:, report_file:), default_review_model
lib/planner/context.rb                   add stdin
lib/planner/cli.rb                       register 'review', add the usage line
lib/planner.rb                           require_relative 'planner/commands/review'
exe/planner                              pass stdin: $stdin
spec/spec_helper.rb                      FakeAgent#review, #default_review_model
spec/planner/commands/review_spec.rb     new
spec/planner/agents/claude_spec.rb       review examples
spec/planner/cli_spec.rb                 stdin: in Context.new
spec/planner/commands/new_spec.rb        stdin: in Context.new
spec/planner/commands/plan_spec.rb       stdin: in Context.new
spec/planner/commands/run_spec.rb        stdin: in Context.new
README.md                                planner review usage line
docs/GLOSSARY.md                         review file entry
```

`planner.gemspec` already ships `lib/**/*.erb`, so it doesn't change. Leave `docs/TODO.md`
alone. It has an uncommitted change that isn't part of this plan.

## Implementation

### `lib/planner/prompts/review.md.erb`

Create it with exactly this content, ending in a single trailing newline. It uses `-%>` tags,
so it must be rendered with `trim_mode: '-'`:

~~~~markdown
# Review Plan

Review the plan `<%= plan_file %>` and write the review to
`<%= review_file %>`. Read the plan, then read the parts of the
codebase it touches and check the plan against them. Do not
read other files in the plan folder.

## Rules

1. Do not modify repository files.
2. You may write only `<%= review_file %>`.
3. Use read-only exploration only.
4. Focus on concrete findings with evidence.
5. Include file paths and line numbers where applicable.
6. Separate high-confidence findings from lower-confidence
   concerns.
7. Write in plain English.

## Focus

<% if lens -%>
Review the plan only through the lens below. Leave out
anything outside it.

<%= lens %>
<% else -%>
Check that:

1. The plan's claims match the code: the files, methods
   and line references it names exist and say what it
   says they do.
2. The steps are complete and in a workable order.
3. Nothing is ambiguous enough that a developer would
   have to ask a question.
4. The Verification section actually proves the change
   works.
5. The plan does not miss risks or regressions.
<% end -%>

## Report

Write `<%= review_file %>` with these sections, in order:

- `# <%= title %>`
<% if lens -%>
- `## Lens`: the lens in one or two sentences
<% end -%>
- `## Summary`
- `## High-confidence findings`
- `## Lower-confidence concerns`
- `## Top recommendations`: a short list

Write "None." under a findings section with nothing in it.

When the file is written, give the user a short
plain-English summary of the review here.
~~~~

`title` is the review file's base name, an em dash, then the plan path as given, with no
backticks (backticks would nest inside the code span). For example:
`REVIEW-001 — docs/plans/x/PLAN-001.md` or `REVIEW-001-a — docs/plans/x/PLAN-001.md`.

### `lib/planner/commands/review.rb`

```ruby
# frozen_string_literal: true

module Planner
  module Commands
    # Renders the review prompt for a plan file and hands it to the agent.
    class Review
      TEMPLATE = File.expand_path('../prompts/review.md.erb', __dir__)
      PLAN_NAME = /\APLAN-(\d+)\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        model, lens = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        number = File.basename(file)[PLAN_NAME, 1]
        raise Error, "#{file} is not a PLAN-<N>.md file" unless number
        raise Error, "#{file} does not exist" unless File.file?(file)

        review_file = review_file(file, number)
        @context.agent.review(prompt(file, review_file, read_lens(lens)), model:, report_file: review_file)
      end

      private

      # REVIEW-<NNN>.md, or the first free REVIEW-<NNN>-a.md, -b ... -z, -aa ... after it.
      def review_file(file, number)
        base = File.join(File.dirname(file), format('REVIEW-%03d', number.to_i))
        path = "#{base}.md"
        suffix = 'a'
        while File.exist?(path)
          path = "#{base}-#{suffix}.md"
          suffix = suffix.succ
        end
        path
      end

      # Reads stdin for "-", and returns nil for no lens or a blank one.
      def read_lens(lens)
        lens = @context.stdin.read if lens == '-'
        lens = lens&.strip
        lens unless lens.nil? || lens.empty?
      end

      def prompt(file, review_file, lens)
        title = "#{File.basename(review_file, '.md')} — #{file}"
        ERB.new(File.read(TEMPLATE), trim_mode: '-')
           .result_with_hash(plan_file: file, review_file:, lens:, title:)
      end

      # Removes the options from args and returns the chosen model and the raw lens.
      def parse(args)
        model = @context.agent.default_review_model
        lens = nil
        OptionParser.new do |opts|
          opts.on('-m', '--model MODEL') { |value| model = value }
          opts.on('-l', '--lens LENS') { |value| lens = value }
        end.parse!(args)
        [model, lens]
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
```

- stdin is read only after the usage, name and existence checks pass.
- If RuboCop objects to the layout, for example `Metrics/MethodLength` or the chained
  `.result_with_hash` indentation, reshape the code to satisfy it. The behaviour above must
  stay the same.

### `lib/planner/agents/claude.rb`

- Update the class comment's interface list to `(#plan, #run, #review, #default_run_model,
  #default_review_model)`.
- Add constants `DEFAULT_REVIEW_MODEL = 'opus'` and `REVIEW_TOOLS = 'Read,Grep,Glob,Write'`.
- Add the methods in the file's existing multi-line `def` style:

```ruby
def review(prompt, model:, report_file:)
  @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                 "--allowedTools=Edit(#{report_file})", prompt)
end

def default_review_model
  DEFAULT_REVIEW_MODEL
end
```

Use the `--flag=value` form for `--tools` and `--allowedTools`. Both take a variadic list in
the `claude` CLI, and the space-separated form could swallow the prompt as another tool name.

### `lib/planner/context.rb`

`Context = Data.define(:root, :agent, :stdin, :stdout, :clock)`. Keep the comment.

### `lib/planner/cli.rb`

- Add `'review' => Commands::Review` to `COMMANDS`, after `'run'`.
- Add a line to `USAGE`, after the `run` line and aligned with it:
  `       planner review [--model <model>] [--lens <text>|-] <plan-file>`

### `lib/planner.rb` and `exe/planner`

- `lib/planner.rb`: `require_relative 'planner/commands/review'` after the `run` require.
- `exe/planner`: add `stdin: $stdin,` to `Context.new`, before `stdout:`.

### Specs

- `spec/spec_helper.rb`, `FakeAgent`:
  - `def review(prompt, model:, report_file:)` records `[:review, prompt, model, report_file]`
  - `def default_review_model` returns `'default-review-model'`
- Add `stdin: StringIO.new` to every existing `Planner::Context.new` in
  `spec/planner/cli_spec.rb`, `spec/planner/commands/new_spec.rb`, `plan_spec.rb` and
  `run_spec.rb`. Change nothing else in those files.
- `spec/planner/agents/claude_spec.rb`:
  - "reviews with the given model, read-only tools and only the report writable":
    `agent.review('review it', model: 'opus', report_file: 'd/REVIEW-001.md')` gives
    `[['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write', '--allowedTools=Edit(d/REVIEW-001.md)', 'review it']]`.
  - "defaults the review model to opus".
- `spec/planner/commands/review_spec.rb` (`:aggregate_failures`, in the tmp dir). Use
  `let(:stdin) { StringIO.new }` and pass it into the context. In `before`, create
  `docs/plans/x/` and write `docs/plans/x/PLAN-001.md`. Examples:
  - The default model: one call, `[0]` is `:review`, `[2]` is `'default-review-model'`.
  - `-m x`, `--model x` and `--model=x` give model `'x'`. `-m ''` raises `UsageError`.
  - Report file: `[3]` is `docs/plans/x/REVIEW-001.md`. With `REVIEW-001.md` present it's
    `REVIEW-001-a.md`. With `REVIEW-001.md` and `-a` present it's `-b`. With `REVIEW-001.md`
    and `-a` through `-z` present it's `-aa`. `docs/plans/x/PLAN-3.md` gives
    `docs/plans/x/REVIEW-003.md`.
  - The prompt (`[1]`) with no lens:
    - starts with `"# Review Plan\n"`
    - contains ``"Review the plan `docs/plans/x/PLAN-001.md`"`` and
      ``"`docs/plans/x/REVIEW-001.md`"``
    - contains ``"`# REVIEW-001 — docs/plans/x/PLAN-001.md`"``
    - contains `'Check that:'`, `'## High-confidence findings'` and `'## Top recommendations'`
    - does not contain `'## Lens'` or `'<%'`
  - With `--lens 'check security'`, the prompt contains `'only through the lens below'`,
    `"check security\n"` and ``'`## Lens`'``, and does not contain `'Check that:'`. Also
    check that `-l 'check security'`, `--lens=check security` and the lens given after the
    file all work.
  - `--lens -` with `stdin` holding `"big\ncontext\n\n"` gives a prompt containing
    `"big\ncontext\n"`, with trailing whitespace stripped.
  - `--lens ''`, `--lens '  '`, and `--lens -` with empty stdin each give the general review
    (`'Check that:'`, no `'## Lens'`).
  - Usage errors: no file, two files, an unknown flag, a missing `-l` value.
  - `docs/plans/x/notes.md` (exists) raises
    `Error, 'docs/plans/x/notes.md is not a PLAN-<N>.md file'`.
  - `docs/plans/x/PLAN-009.md` (missing) raises
    `Error, 'docs/plans/x/PLAN-009.md does not exist'`.
  - `nope.md` (missing *and* a bad name) raises the name error, which proves the name check
    runs first.
- `spec/planner/cli_spec.rb`: no new examples. The `USAGE` examples compare against the
  constant, so they pick up the new line.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. Add a `planner review`
usage line after the `planner run` line, for example:

```
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it; `--lens` narrows the review, `--lens -` reads the lens from stdin (default model `opus`).
```

### `docs/GLOSSARY.md`

Add after the plan file entry:

```
- **review file**: `REVIEW-<NNN>.md`, or `REVIEW-<NNN>-<letter>.md` for a later review of the same plan. A plain-English review of a plan file, written by `planner review`.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new and updated ones, plus RuboCop with
   no offences.
2. Render the prompt by hand and read it, with and without a lens. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def review(x, model:, report_file:) = puts(x, model, report_file); def default_review_model = "opus" }.new; Planner::Commands::Review.new(Planner::Context.new(root: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' docs/plans/202610281426-add-review-sub-command/PLAN-001.md`
   The output starts with `# Review Plan`, names `…/PLAN-001.md` and `…/REVIEW-001.md`,
   shows the five-point checklist and no `## Lens` line, and ends with `opus` and the review
   path. There are no ERB leftovers and no stray blank lines where the `<% … -%>` tags were.
   Run it again with `--lens -` appended and `echo "check security" |` in front. The Focus
   section now shows the lens text instead of the checklist, and the Report list includes
   `## Lens`.
3. `bundle exec rake install` succeeds, then:
   - `planner review README.md` exits 1 with `[planner] README.md is not a PLAN-<N>.md file`.
   - `planner` with no args prints the usage text, including the `planner review` line.
   - `gem contents planner` lists `lib/planner/prompts/review.md.erb`.
4. Running `planner review <plan-file>` against a real `claude` session is a manual smoke check
   for the user. The agent does not run it. The user confirms three things: the session has
   no Bash tool, writing the report is not prompted, and the review file appears in the plan
   folder.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib exe spec README.md docs/GLOSSARY.md docs/plans/202610281426-add-review-sub-command
```

That last path stages this folder's `ITERATION-001.md` and `PLAN-001.md`. Do not stage
`docs/TODO.md`. `mise.toml` was already staged before this plan and must stay out of this
commit. Write the message to a file and commit only the paths above:

```
git commit -F <file> -- lib exe spec README.md docs/GLOSSARY.md docs/plans/202610281426-add-review-sub-command
```

Suggested message:

```
Add planner review subcommand

Have the agent review a PLAN-<N>.md file against the codebase and
write a plain-English REVIEW-<N>.md next to it, with a letter suffix
when earlier reviews exist. An optional --lens narrows the review and
can be piped on stdin with --lens -. The session gets read-only tools
and may write only the report file.
```
