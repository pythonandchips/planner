## Run summary

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-29T16:09:22Z |
| Finished | 2026-10-29T16:09:56Z |
| Elapsed | 34s |
| Model | sonnet |
| Tokens | ~45k (estimate) |

---

# PLAN-003 — Apply review suggestions to the plan and mark them in the review

In a `planner review` session, the user can now ask the agent to apply suggestions from the
review. The agent edits the plan file under review, then marks each applied finding, concern or
recommendation in the review file with an `**Applied:**` line, and replies in a fixed format. The
instruction goes in the review prompt template, `lib/planner/prompts/review.md.erb`. Two of its
rules are relaxed so the plan file may be written, and the agent auto-approves writes to the plan
file as well as the report. Also in scope: specs, the README, the glossary and two TODO lines.
Everything PLAN-001 and PLAN-002 settled still applies: the report name, headings, summary
format, lens handling and tool list don't change.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the instruction lives | The review prompt template, `lib/planner/prompts/review.md.erb`. No shipped skill. |
| Who edits the plan | The review agent, when the user asks it to apply suggestions |
| Permission for plan writes | Auto-approved, like the report file |
| Tool list | Unchanged: `--tools=Read,Grep,Glob,Write`. No Edit tool. |
| Agent interface | `review(prompt, model:, report_file:, plan_file:)`. `claude` gets one flag, `--allowedTools=Edit(<report>),Edit(<plan>)`. `FakeAgent` records `plan_file` too. |
| How applied items are marked | Inline: an `**Applied:** <what changed in the plan, in one line>` line under each applied finding, concern or recommendation |
| Statuses recorded | Applied only. Items that weren't applied are left as written. |
| Reply after applying | A fixed format, given in the template |
| Prompt wording | Exactly the template text in Implementation (the user approved the draft) |
| Specs | Key-string checks, same depth as PLAN-001 and PLAN-002 |
| Docs | README `planner review` line (through `update-readme`), the glossary "review file" entry, and remove TODO lines 9 and 11 |
| `docs/TODO.md` in the commit | Stage the whole file, including the user's existing uncommitted line |
| Verification | `bundle exec rake`, and render the prompt against a throwaway plan in `$TMPDIR`. No manual smoke check. |

## Files to change

```
lib/planner/prompts/review.md.erb        relax rules 1 and 2, add "Applying suggestions"
lib/planner/commands/review.rb           pass plan_file: to the agent
lib/planner/agents/claude.rb             review takes plan_file:, allows Edit on it
spec/spec_helper.rb                      FakeAgent#review records plan_file
spec/planner/agents/claude_spec.rb       update the review example
spec/planner/commands/review_spec.rb     plan file and prompt examples
README.md                                clause on the planner review line
docs/GLOSSARY.md                         sentence on the review file entry
docs/TODO.md                             remove lines 9 and 11
```

## Implementation

### `lib/planner/prompts/review.md.erb`

Replace rules 1 and 2:

```
1. Do not modify repository files.
2. You may write only `<%= review_file %>`.
```

with exactly:

```
1. Do not modify repository files, except the plan
   as described under "Applying suggestions".
2. You may write only `<%= review_file %>`, and
   `<%= plan_file %>` when the user asks you to
   apply suggestions.
```

Rules 3 to 7 stay as they are.

At the end of the file, after the last line (`"None." after a label with nothing under it.`)
and one blank line, add exactly the text below. The inner fence is a plain three-backtick fence
inside the template. The file still ends in a single trailing newline, after the closing fence.

~~~~markdown
## Applying suggestions

If the user asks you to apply suggestions from the
review, edit `<%= plan_file %>` to make only those
changes. Then update `<%= review_file %>`: under
each finding, concern or recommendation you
applied, add the line

**Applied:** <what changed in the plan, in one line>

Change nothing else in the review. Then reply here
in exactly this format:

```
Applied to `<%= plan_file %>` and marked in
`<%= review_file %>`:
- <the item in one line>: <what changed in the plan>
```
~~~~

`plan_file` is already passed to the template, so `Commands::Review#prompt` doesn't change.

### `lib/planner/commands/review.rb`

In `call`, replace the last line with:

```ruby
        @context.agent.review(prompt(file, review_file, read_lens(lens)),
                              model:, report_file: review_file, plan_file: file)
```

Nothing else changes. If RuboCop objects to the layout, reshape it to satisfy RuboCop. The
behaviour must stay the same.

### `lib/planner/agents/claude.rb`

Replace `review` with:

```ruby
      def review(prompt, model:, report_file:, plan_file:)
        @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                       "--allowedTools=Edit(#{report_file}),Edit(#{plan_file})", prompt)
      end
```

Keep the `--flag=value` form (see PLAN-001). The class comment and the constants don't change.

### Specs

- `spec/spec_helper.rb`, `FakeAgent`: change `review` to

  ```ruby
    def review(prompt, model:, report_file:, plan_file:)
      @calls << [:review, prompt, model, report_file, plan_file]
    end
  ```

- `spec/planner/agents/claude_spec.rb`: replace the "reviews with the given model, read-only
  tools and only the report writable" example with:

  ```ruby
    it 'reviews with the given model, read-only tools and only the report and plan writable' do
      agent.review('review it', model: 'opus', report_file: 'd/REVIEW-001.md', plan_file: 'd/PLAN-001.md')

      expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write',
                            '--allowedTools=Edit(d/REVIEW-001.md),Edit(d/PLAN-001.md)', 'review it']])
    end
  ```

- `spec/planner/commands/review_spec.rb`:
  - After the "uses the agent's default model" example, add:

    ```ruby
      it 'passes the plan file to the agent' do
        command.call([plan])

        expect(call[4]).to eq('docs/plans/x/PLAN-001.md')
      end
    ```

  - In `describe 'the prompt with no lens'`, after the "has no lens line in the summary"
    example, add:

    ```ruby
        it 'lets the agent apply suggestions to the plan' do
          expect(prompt).to include("You may write only `docs/plans/x/REVIEW-001.md`, and\n   " \
                                    '`docs/plans/x/PLAN-001.md` when the user asks you to',
                                    '## Applying suggestions', 'edit `docs/plans/x/PLAN-001.md` to make only those',
                                    '**Applied:** <what changed in the plan, in one line>',
                                    "Applied to `docs/plans/x/PLAN-001.md` and marked in\n`docs/plans/x/REVIEW-001.md`:")
        end
    ```

  - Change nothing else in the file. If RuboCop objects to the wrapping, rewrap it. The strings
    checked must stay the same.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. On the existing
`planner review` line, add a clause before `(default model opus)`, for example:

```
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it, then summarise it in the session under the same headings; `--lens` narrows the review, `--lens -` reads the lens from stdin; ask in the session and it applies suggestions to the plan and marks each one `**Applied:**` in the review (default model `opus`).
```

### `docs/GLOSSARY.md`

Append one sentence to the end of the existing "review file" entry:

```
- **review file**: `REVIEW-<NNN>.md`, or `REVIEW-<NNN>-<letter>.md` for a later review of the same plan. A plain-English review of a plan file, written by `planner review`. When the user has the review session apply suggestions to the plan, each applied item gets an `**Applied:**` line.
```

### `docs/TODO.md`

Delete these two lines and change nothing else. Keep the user's uncommitted last line.

```
- allow the review command to edit a plan
- Add a skill to update the plan when doing a review.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new and changed examples, plus RuboCop
   with no offences.
2. Render the prompt against a throwaway plan, so existing `REVIEW-*.md` files in the repo
   don't change the expected review name. As separate commands, from the repo root:
   - `mkdir -p "$TMPDIR/review-check"`
   - `printf 'the plan\n' > "$TMPDIR/review-check/PLAN-001.md"`
   - `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def review(x, model:, report_file:, plan_file:) = puts(x, model, report_file, plan_file); def default_review_model = "opus" }.new; Planner::Commands::Review.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' "$TMPDIR/review-check/PLAN-001.md"`

   Check that:
   - Rules 1 and 2 read as in Implementation, with rule 2 naming `…/review-check/REVIEW-001.md`
     and `…/review-check/PLAN-001.md`.
   - The prompt ends with the "Applying suggestions" section. Its fenced reply format starts
     with ``Applied to `…/review-check/PLAN-001.md` and marked in``.
   - There are no ERB leftovers and no stray blank lines.
   - The output ends with `opus`, the review path and the plan path, one per line.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib spec README.md docs/GLOSSARY.md docs/TODO.md docs/plans/202610281426-add-review-sub-command/ITERATION-003.md docs/plans/202610281426-add-review-sub-command/PLAN-003.md
```

This stages the whole of `docs/TODO.md`, including the user's existing uncommitted line. It
leaves out any `REVIEW-*.md` files in the plan folder. Write the message to a file in the
scratchpad directory, then commit only the paths above:

```
git commit -F <file> -- lib spec README.md docs/GLOSSARY.md docs/TODO.md docs/plans/202610281426-add-review-sub-command/ITERATION-003.md docs/plans/202610281426-add-review-sub-command/PLAN-003.md
```

Suggested message. Follow the `commit-message` skill, which adds the `Assisted-by:` trailer:

```
Let planner review apply suggestions to the plan

In a review session the user can now ask the agent to apply the
review's suggestions. The agent edits the plan file, marks each
applied finding, concern or recommendation with an Applied line in
the review, and replies in a fixed format. Writes to the plan file
are auto-approved like the report.

Also remove the two TODO items this covers.
```
