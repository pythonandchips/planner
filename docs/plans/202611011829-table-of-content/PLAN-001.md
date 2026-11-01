# PLAN-001 — Add `planner toc` and keep the table of contents up to date

Add a `planner toc [--model <model>] <plan-folder>` command that runs the agent headless
(`claude -p`) to write `TABLE_OF_CONTENT.md` in a plan folder. The file has a short
plain-English summary of the folder's work, then every `.md` file in the folder with a
one-line summary, and `Completed` or `Not completed` on each plan. The format lives in one
shared ERB partial. The `plan`, `explore`, `review` and `run` prompts render the same partial
in update mode, so when the file already exists the agent updates it after writing its own
file. The README and glossary are updated.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Command name and argument | `planner toc <plan-folder>` |
| How it runs | Headless `claude -p`. The agent writes the file and exits |
| Model | `--model`/`-m` flag. Default `haiku`, via a new `default_toc_model` on the agent |
| Tools for `planner toc` | `--tools=Read,Grep,Glob,Write` and `--allowedTools=Edit(<folder>/TABLE_OF_CONTENT.md)` |
| File name | `TABLE_OF_CONTENT.md` (as in the brief) |
| How completion is decided | From the run stats: a `\| Status \| Completed \|` row in the `## Stats` block at the end of the plan, or in the older `## Run summary` block at the top |
| Status values | `Completed` or `Not completed`. A stopped plan, or one with no stats, is `Not completed` |
| List layout | Bullets: `- [FILE](FILE) — <summary>`, with ` (<status>)` after the summary on plan lines only |
| Order | Grouped by number. Within a number: ITERATION, FINDINGS, PLAN, REVIEW. Lettered files (`-a`, `-b` … `-z`, `-aa`) go straight after their base file |
| Which files are listed | Every `.md` in the folder except `TABLE_OF_CONTENT.md` |
| Other `.md` files | At the end, alphabetical |
| Top of the file | `# Table of contents — <folder name>`, then `## Summary` (two to four sentences), then `## Files` |
| `planner toc` when the file exists | Rewrite it from scratch |
| `planner toc` output | The agent replies exactly ``Table of contents written to `<path>`.`` |
| Argument errors | No folder or more than one → `UsageError`. Not a directory → `Error` "`<folder> is not a directory`". An empty folder is not an error |
| How plan/explore/review/run update it | Prompt instruction: if the file exists, the agent edits it. It is never created by them. Review and explore get `Edit(<toc>)` in `--allowedTools` |
| What an update changes | Add or replace the line for each file the agent wrote, refresh every plan's status from its stats, rewrite the Summary. Leave every other line as it is |
| Explore timing | Only at finish, after the stats |
| Review timing | After writing the review, and again after applying suggestions |
| Run | Also updates it (beyond the brief), after writing the stats, on finish and on stop. On finish it stages the file with the commit if it updated it. On a stop it does not commit |
| Review's "do not read other files in the plan folder" rule | Exception: it may read the table of contents and the folder's `PLAN-*.md` files only to update the table of contents, never to inform the review |
| Format spec location | One shared partial, `lib/planner/prompts/_table_of_content.md.erb`, rendered into every prompt |
| Plan prompt's Commit section | If the table of contents exists, the generated plan lists it in what to stage |
| README | Add a `planner toc` bullet that also says plan/explore/review/run keep an existing file up to date. Other bullets unchanged. Use the `update-readme` skill |
| Glossary | Add a **table of contents** entry |
| This folder's own table of contents | Do not generate one as part of this change |

## Files to create / change

```
lib/planner/table_of_content.rb                 new: file name, path, renders the partial
lib/planner/prompts/_table_of_content.md.erb    new: shared format (+ update rules)
lib/planner/prompts/toc.md.erb                  new: the toc prompt
lib/planner/commands/toc.rb                     new: the toc command
lib/planner.rb                                  require the two new Ruby files
lib/planner/cli.rb                              register `toc`, add a usage line
lib/planner/agents/claude.rb                    #toc, #default_toc_model; Edit(<toc>) for review and explore
lib/planner/commands/plan.rb                    pass toc_file and table_of_content
lib/planner/commands/explore.rb                 same, and toc_file: to the agent
lib/planner/commands/review.rb                  same, and toc_file: to the agent
lib/planner/commands/run.rb                     pass toc_file and table_of_content
lib/planner/prompts/plan.md.erb                 step 4 note, step 5, Table of contents section
lib/planner/prompts/explore.md.erb              rule 2, step 8, Table of contents section
lib/planner/prompts/review.md.erb               rules 1–2, read exception, Report and Applying, section
lib/planner/prompts/run.md.erb                  rules 1 and 6, Table of contents section
spec/spec_helper.rb                             FakeAgent: toc, default_toc_model, toc_file: kwargs
spec/planner/table_of_content_spec.rb           new
spec/planner/commands/toc_spec.rb               new
spec/planner/agents/claude_spec.rb              toc, default, new allowedTools
spec/planner/cli_spec.rb                        dispatches toc
spec/planner/commands/{plan,explore,review,run}_spec.rb   table of contents expectations
README.md                                       `planner toc` bullet
docs/GLOSSARY.md                                **table of contents** entry
```

## Implementation

### 1. `lib/planner/table_of_content.rb` (new)

```ruby
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
```

In `lib/planner.rb` add `require_relative 'planner/table_of_content'` after the
`skill_catalog` require, and `require_relative 'planner/commands/toc'` after the
`commands/explore` require.

### 2. `lib/planner/prompts/_table_of_content.md.erb` (new)

Exactly:

````
<% if update -%>
If `<%= toc_file %>` exists, update it when this
prompt says to. Read every `PLAN-*.md` in
`<%= folder %>/` for its status, then:

- add a line for each file you wrote, or replace its
  line if it is already listed, in its place in the
  order below
- set every plan's status from its stats
- rewrite the Summary to cover the folder as the
  lines now describe it
- leave every other line as it is

If `<%= toc_file %>` does not exist, do not create it.

<% end -%>
The table of contents lists the files in
`<%= folder %>/` in exactly this format:

```markdown
# Table of contents — <%= name %>

## Summary

<two to four plain-English sentences on what has been done in this folder and where it stands>

## Files

- [<file>](<file>) — <what the file holds, in one line>
- [PLAN-<NNN>.md](PLAN-<NNN>.md) — <what the plan changes, in one line> (<status>)
```

- List every `.md` file in the folder except
  `TABLE_OF_CONTENT.md`.
- Order the files by number. Within a number, put
  `ITERATION`, then `FINDINGS`, then `PLAN`, then
  `REVIEW`, and put lettered files such as
  `FINDINGS-001-a.md` straight after their base file,
  in letter order (`a`, `b` ... `z`, `aa`). Put any
  other `.md` files at the end, alphabetically.
- Only plan lines have a status. It is `Completed`
  when the plan's stats have a `| Status | Completed |`
  row, in the `## Stats` block at the end of the file
  or the older `## Run summary` block at the top.
  Otherwise it is `Not completed`.
````

### 3. `lib/planner/prompts/toc.md.erb` (new)

Exactly:

````
# Table of Contents

Write `<%= toc_file %>`, a table of contents for the
plan folder `<%= folder %>/`. Read every `.md` file in
the folder except `TABLE_OF_CONTENT.md`. If
`<%= toc_file %>` already exists, replace it entirely
and do not reuse anything in it.

## Rules

1. Do not modify repository files.
2. You may write only `<%= toc_file %>`.
3. Use read-only exploration only.

## Format

<%= table_of_content %>

## Reply

When the file is written, reply with exactly:

```
Table of contents written to `<%= toc_file %>`.
```
````

### 4. `lib/planner/commands/toc.rb` (new)

```ruby
# frozen_string_literal: true

module Planner
  module Commands
    # Renders the toc prompt for a plan folder and hands it to the agent.
    class Toc
      TEMPLATE = File.expand_path('../prompts/toc.md.erb', __dir__)

      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        folder = args.first.chomp('/')
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        toc_file = TableOfContent.path(folder)
        @context.agent.toc(prompt(folder, toc_file), model:, toc_file:)
      end

      private

      def prompt(folder, toc_file)
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          folder:, toc_file:, table_of_content: TableOfContent.section(folder, update: false)
        )
      end

      # Removes the options from args and returns the chosen model.
      def parse(args)
        model = @context.agent.default_toc_model
        OptionParser.new { |opts| opts.on('-m', '--model MODEL') { |value| model = value } }.parse!(args)
        model
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
```

### 5. `lib/planner/cli.rb`

- Add `'toc' => Commands::Toc` after `'explore' => Commands::Explore,` in `COMMANDS`.
- Add the usage line `       planner toc [--model <model>] <plan-folder>` after the
  `planner explore` line in `USAGE` (same indentation as the other continuation lines).

### 6. `lib/planner/agents/claude.rb`

- Class comment: add `#toc` after `#explore` and `#default_toc_model` after
  `#default_explore_model` in the interface list (rewrap to fit the line length).
- Constants, after `EXPLORE_TOOLS`:

  ```ruby
  DEFAULT_TOC_MODEL = 'haiku'
  TOC_TOOLS = 'Read,Grep,Glob,Write'
  ```

- `review` takes `toc_file:` and its allowed tools become
  `"--allowedTools=Edit(#{report_file}),Edit(#{plan_file}),Edit(#{toc_file})"`.
- `explore` takes `toc_file:` and its allowed tools become
  `"--allowedTools=Edit(#{findings_file}),Edit(#{toc_file}),WebFetch"`.
- After `explore`, add:

  ```ruby
  def toc(prompt, model:, toc_file:)
    @executor.call('claude', '-p', '--model', model, "--tools=#{TOC_TOOLS}",
                   "--allowedTools=Edit(#{toc_file})", prompt)
  end
  ```

- After `default_explore_model`, add `def default_toc_model` returning `DEFAULT_TOC_MODEL`.

### 7. Commands that render an update section

In each, the folder is the folder of the given file (`File.dirname(file)`), and two extra
values go into `result_with_hash`: `toc_file: TableOfContent.path(folder)` and
`table_of_content: TableOfContent.section(folder, update: true)`.

- `lib/planner/commands/plan.rb`: in `prompt`, add both to the existing hash.
- `lib/planner/commands/run.rb`: in `prompt`, compute `folder = File.dirname(file)` and add both.
- `lib/planner/commands/explore.rb`: in `prompt`, add both. In `call`, pass
  `toc_file: TableOfContent.path(File.dirname(file))` to `@context.agent.explore`.
- `lib/planner/commands/review.rb`: in `prompt`, add both (folder from the plan file). In
  `call`, pass `toc_file: TableOfContent.path(File.dirname(file))` to `@context.agent.review`.

### 8. `lib/planner/prompts/plan.md.erb`

- Step 4: append this sentence to the end of the step: ``If `<%= toc_file %>` exists, list
  it in what to stage.``
- After step 4, add:

  ```
  5. **Update the table of contents.** After writing `<%= plan_file %>`, update
     `<%= toc_file %>` as described under "Table of contents".
  ```

- At the end of the file, after the `## Notes` bullets, add a blank line, then:

  ```
  ## Table of contents

  <%= table_of_content %>
  ```

### 9. `lib/planner/prompts/explore.md.erb`

- Rule 2 becomes:

  ```
  2. You may write only `<%= findings_file %>`, and
     `<%= toc_file %>` as described under "Table of
     contents".
  ```

- Step 8 becomes:

  ```
  8. **Finish** when the user tells you to: rewrite
     `<%= findings_file %>` a final time, add the stats,
     update `<%= toc_file %>` as described under
     "Table of contents", and reply in the format under
     "Summary for the user".
  ```

- Between the stats leave-out bullet and `## Summary for the user`, add:

  ```
  ## Table of contents

  <%= table_of_content %>
  ```

  with one blank line before and after.

### 10. `lib/planner/prompts/review.md.erb`

- Intro: replace `Do not\nread other files in the plan folder.` with:

  ```
  Do not
  read other files in the plan folder, except to update
  the table of contents as described under "Table of
  contents". Never use them to inform the review.
  ```

- Rules 1 and 2 become:

  ```
  1. Do not modify repository files, except the plan
     and the table of contents as described under
     "Applying suggestions" and "Table of contents".
  2. You may write only `<%= review_file %>`,
     `<%= plan_file %>` when the user asks you to
     apply suggestions, and `<%= toc_file %>` as
     described under "Table of contents".
  ```

- `## Report`: after `Write "None." under a findings section with nothing in it.`, add a
  blank line, then:

  ```
  After writing `<%= review_file %>`, update
  `<%= toc_file %>` as described under "Table of
  contents".
  ```

- `## Applying suggestions`: replace `Change nothing else in the review. Then reply here\nin exactly this format:` with:

  ```
  Change nothing else in the review. Then update
  `<%= toc_file %>` as described under "Table of
  contents". Then reply here in exactly this format:
  ```

- At the end of the file add a blank line, then:

  ```
  ## Table of contents

  <%= table_of_content %>
  ```

### 11. `lib/planner/prompts/run.md.erb`

- Rule 1: replace `nothing\n   else apart from the stats below.` with
  `nothing\n   else apart from the stats and the table of\n   contents below.`
- Rule 6 becomes:

  ```
  6. Write the stats when you finish and when you
     stop, then update the table of contents as
     described under "Table of contents". When you
     finish, do both after every Verification step
     passes and before the Commit step, and
     stage `<%= plan_file %>` with the commit even if
     the Commit section does not list it, along with
     `<%= toc_file %>` if you updated it. When you
     stop, do both but still do not commit.
  ```

- Between the stats leave-out bullets and `## Plan`, add:

  ```
  ## Table of contents

  <%= table_of_content %>
  ```

  with one blank line before and after.

### 12. `spec/spec_helper.rb` (FakeAgent)

- `review(prompt, model:, report_file:, plan_file:, toc_file:)` records
  `[:review, prompt, model, report_file, plan_file, toc_file]`.
- `explore(prompt, model:, findings_file:, toc_file:)` records
  `[:explore, prompt, model, findings_file, toc_file]`.
- Add `toc(prompt, model:, toc_file:)` recording `[:toc, prompt, model, toc_file]`, and
  `default_toc_model` returning `'default-toc-model'`.

### 13. Specs

`spec/planner/table_of_content_spec.rb` (new):

- `path('docs/plans/x')` is `'docs/plans/x/TABLE_OF_CONTENT.md'`.
- `section('docs/plans/x', update: false)` includes `'# Table of contents — x'`,
  `'| Status | Completed |'`, `'Not completed'`, `'except\n  `TABLE_OF_CONTENT.md`'`; does not
  include ``'If `docs/plans/x/TABLE_OF_CONTENT.md` exists'`` or `'<%'`.
- `section('docs/plans/x', update: true)` includes
  ``'If `docs/plans/x/TABLE_OF_CONTENT.md` exists'``, `'do not create it'` and
  `'# Table of contents — x'`.

`spec/planner/commands/toc_spec.rb` (new), in the style of `explore_spec.rb`, with
`docs/plans/x` created in a `before`:

- Uses the agent's default model: one call, `call[0] == :toc`, `call[2] == 'default-toc-model'`.
- Accepts `-m x`, `--model x`, `--model=x`; rejects an empty model with `UsageError`.
- Passes `docs/plans/x/TABLE_OF_CONTENT.md` as `call[3]`, also when given `docs/plans/x/`.
- The prompt starts with `"# Table of Contents\n"`, has no `<%`, includes
  ``'You may write only `docs/plans/x/TABLE_OF_CONTENT.md`.'``, `'replace it entirely'`,
  `'# Table of contents — x'` and ``'Table of contents written to `docs/plans/x/TABLE_OF_CONTENT.md`.'``,
  and does not include `'do not create it'`.
- Raises `UsageError` for no args, two args, an unknown flag and a missing `-m` value.
- Raises `Planner::Error, 'docs/plans/nope is not a directory'` for a missing folder, and
  the same kind of message for a path that is a file.

`spec/planner/agents/claude_spec.rb`:

- Review example: pass `toc_file: 'd/TABLE_OF_CONTENT.md'` and expect
  `'--allowedTools=Edit(d/REVIEW-001.md),Edit(d/PLAN-001.md),Edit(d/TABLE_OF_CONTENT.md)'`.
- Explore example: pass `toc_file: 'd/TABLE_OF_CONTENT.md'` and expect
  `'--allowedTools=Edit(d/FINDINGS-001.md),Edit(d/TABLE_OF_CONTENT.md),WebFetch'`.
- New: `agent.toc('list it', model: 'haiku', toc_file: 'd/TABLE_OF_CONTENT.md')` calls
  `['claude', '-p', '--model', 'haiku', '--tools=Read,Grep,Glob,Write', '--allowedTools=Edit(d/TABLE_OF_CONTENT.md)', 'list it']`.
- New: `default_toc_model` is `'haiku'`.

`spec/planner/cli_spec.rb`: add `it 'dispatches toc'` expecting `cli.call(%w[toc nope])`
to return 1 and stderr to be `"[planner] nope is not a directory\n"`.

`spec/planner/commands/review_spec.rb`:

- `'passes the plan file to the agent'`: also expect `call[5]` to be
  `'docs/plans/x/TABLE_OF_CONTENT.md'`.
- Update `'lets the agent apply suggestions to the plan'` so its first string matches the
  new rule 2 (``"You may write only `docs/plans/x/REVIEW-001.md`,\n   `docs/plans/x/PLAN-001.md` when the user asks you to"``).
- New example: the prompt includes ``'If `docs/plans/x/TABLE_OF_CONTENT.md` exists'``,
  `'Never use them to inform the review.'`,
  ``"After writing `docs/plans/x/REVIEW-001.md`, update"`` and
  `'Then update'` within `## Applying suggestions`.

`spec/planner/commands/explore_spec.rb`:

- In `describe 'the findings file'`, add an example expecting `call[4]` to be
  `'docs/plans/x/TABLE_OF_CONTENT.md'`.
- New prompt example: includes ``'If `docs/plans/x/TABLE_OF_CONTENT.md` exists'`` and
  ``"update `docs/plans/x/TABLE_OF_CONTENT.md` as described under"``.

`spec/planner/commands/plan_spec.rb`: new example: the prompt for
`docs/plans/x/ITERATION-001.md` includes `'5. **Update the table of contents.**'`,
``'If `docs/plans/x/TABLE_OF_CONTENT.md` exists, list'`` and `'## Table of contents'`.

`spec/planner/commands/run_spec.rb`: new example: the prompt includes
`'the stats and the table of'`, ``'`./TABLE_OF_CONTENT.md` if you updated it'`` and
``'If `./TABLE_OF_CONTENT.md` exists'`` (the run spec's plan file is `PLAN-001.md` in the
current directory). Existing examples keep passing unchanged.

If rubocop flags line length or example length, wrap or add the same
`# rubocop:disable RSpec/ExampleLength` comment the existing specs use, without changing
the strings.

### 14. `docs/GLOSSARY.md`

After the **findings file** entry, add:

```markdown
- **table of contents**: `TABLE_OF_CONTENT.md` in a plan folder. A short plain-English summary of the folder's work, then every file in it with a one-line summary, and `Completed` or `Not completed` on each plan file. Written by `planner toc`, and updated by `planner plan`, `planner explore`, `planner review` and `planner run` when it exists.
```

### 15. `README.md`

Use the `update-readme` skill. After the `planner explore` bullet, add:

```markdown
- `planner toc [--model <model>] <plan-folder>`: have the agent write `TABLE_OF_CONTENT.md` in a plan folder, replacing any existing one: a short summary of the work, then every file with a one-line summary and, for plans, whether they are completed. Once it exists, `planner plan`, `explore`, `review` and `run` keep it up to date (default model `haiku`).
```

Change nothing else.

## Verification

1. `bundle exec rake` passes (specs and rubocop).
2. `bundle exec exe/planner` prints usage including `planner toc [--model <model>] <plan-folder>`
   and exits 1.
3. `bundle exec exe/planner toc docs/plans/nope` prints
   `[planner] docs/plans/nope is not a directory` and exits 1.
4. `grep -c "table_of_content %>" lib/planner/prompts/*.erb` prints `1` for `explore`,
   `plan`, `review`, `run` and `toc`, and `0` for `_table_of_content.md.erb`.
5. `git status` shows no `TABLE_OF_CONTENT.md` anywhere (do not run `planner toc` for real).

## Commit

Commit only after every change above is made and every Verification step passes. Do not
commit before.

Stage:

```
lib/planner/table_of_content.rb
lib/planner/prompts/_table_of_content.md.erb
lib/planner/prompts/toc.md.erb
lib/planner/commands/toc.rb
lib/planner.rb
lib/planner/cli.rb
lib/planner/agents/claude.rb
lib/planner/commands/plan.rb
lib/planner/commands/explore.rb
lib/planner/commands/review.rb
lib/planner/commands/run.rb
lib/planner/prompts/plan.md.erb
lib/planner/prompts/explore.md.erb
lib/planner/prompts/review.md.erb
lib/planner/prompts/run.md.erb
spec/spec_helper.rb
spec/planner/table_of_content_spec.rb
spec/planner/commands/toc_spec.rb
spec/planner/agents/claude_spec.rb
spec/planner/cli_spec.rb
spec/planner/commands/plan_spec.rb
spec/planner/commands/explore_spec.rb
spec/planner/commands/review_spec.rb
spec/planner/commands/run_spec.rb
README.md
docs/GLOSSARY.md
docs/plans/202611011829-table-of-content/ITERATION-001.md
docs/plans/202611011829-table-of-content/PLAN-001.md
```

Write the message with the `commit-message` skill. Suggested message:

```
Add planner toc for a plan folder's table of contents

Plan folders with many iterations are hard to scan, since every
file is a numbered ITERATION, FINDINGS, PLAN or REVIEW. `planner toc`
has the agent write TABLE_OF_CONTENT.md: a short summary, then each
file with a one-line summary and whether each plan is completed.
Once the file exists, plan, explore, review and run update it after
writing their own file.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-01T18:50:17Z |
| Finished | 2026-11-01T18:56:20Z |
| Elapsed | 6m 3s |
| Model | sonnet |
| Tokens | ~90k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sed -i "s/expect(prompt).not_to include('\| Status \|', ...)/..."` | Failed: the `\|` in the pattern clashed with the delimiter, so it was redone with the Edit tool | Use the Edit tool for edits containing `\|` |
