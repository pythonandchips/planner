# PLAN-002 — Fix the format of the review summary

The agent's in-session summary at the end of `planner review` comes out in a different shape
each time. This change replaces the last paragraph of `lib/planner/prompts/review.md.erb` with
a "Summary for the user" section that gives the exact format. The format mirrors the report's
headings, lists every finding as a one-liner, and adds a Lens line only when a lens is given.
Also in scope: prompt specs and a short README clause. Everything PLAN-001 settled still
applies: the report file, its headings, the tools, the lens handling and the command code
don't change.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the format goes | The review prompt template, `lib/planner/prompts/review.md.erb`. It replaces the closing "When the file is written…" paragraph. |
| Shape of the summary | Mirrors the report headings as bold labels, after a "Review written to `<review file>`." line: Summary, High-confidence findings, Lower-confidence concerns, Top recommendations |
| Findings in the summary | Every finding and every concern, one line each |
| Lens line | `**Lens:**` line only when a lens is given, as with the report's `## Lens` |
| List style | Findings and concerns as `-` bullets. Top recommendations numbered `1.`, `2.` … |
| File references | Each finding line starts with its `file:line` when there is one |
| Empty groups | "None." after a label with nothing under it |
| Prompt wording | Exactly the template text in Implementation (the user approved the draft) |
| Specs | Key-string checks in `review_spec.rb`, same depth as PLAN-001 |
| README | A short clause appended to the existing `planner review` line, through `update-readme` |
| Manual smoke check | Not part of this plan's verification |

## Files to change

```
lib/planner/prompts/review.md.erb        replace the closing paragraph with the summary section
spec/planner/commands/review_spec.rb     summary format examples
README.md                                short clause on the planner review line
```

No Ruby code changes. `Commands::Review` already passes `review_file` and `lens` to the
template.

## Implementation

### `lib/planner/prompts/review.md.erb`

Delete the last two lines of the file:

```
When the file is written, give the user a short
plain-English summary of the review here.
```

In their place, after the existing `Write "None." under a findings section with nothing in it.`
line and one blank line, put exactly this text. The file still ends in a single trailing
newline. The fence is a plain three-backtick fence inside the template. The `<% … -%>` tags
sit at column 0 so that, with `trim_mode: '-'`, they leave no blank lines behind:

~~~~markdown
## Summary for the user

When the file is written, reply here with a plain-English
summary in exactly this format:

```
Review written to `<%= review_file %>`.

<% if lens -%>
**Lens:** <the lens in one sentence>

<% end -%>
**Summary:** <one or two sentences>

**High-confidence findings:**
- <file:line where there is one>: <the finding in one line>

**Lower-confidence concerns:**
- <file:line where there is one>: <the concern in one line>

**Top recommendations:**
1. <the recommendation in one line>
```

List every finding and concern, one line each. Write
"None." after a label with nothing under it.
~~~~

With no lens, the line after `Review written to …` is a blank line, then `**Summary:**`. With a
lens, the `**Lens:**` line and one blank line come between them.

### `spec/planner/commands/review_spec.rb`

Add the examples below exactly as written. They are wrapped to stay within RuboCop's
120-character `Layout/LineLength` and 5-line `RSpec/ExampleLength` limits, which is why the
no-lens checks are split into two examples.

- In `describe 'the prompt with no lens'`, after the existing
  "has no lens section and no ERB leftovers" example (which stays as it is), add:

  ```ruby
      it 'has the summary format' do
        expect(prompt).to include('## Summary for the user',
                                  "Review written to `docs/plans/x/REVIEW-001.md`.\n\n**Summary:**",
                                  '**High-confidence findings:**', '**Lower-confidence concerns:**',
                                  '**Top recommendations:**', '1. <the recommendation in one line>',
                                  'List every finding and concern, one line each.')
      end

      it 'has no lens line in the summary' do
        expect(prompt).not_to include('**Lens:**')
      end
  ```

- In `describe 'the prompt with a lens'`, after the "narrows the review to the lens" example,
  add:

  ```ruby
      it 'adds a lens line to the summary' do
        expect(prompt_for('--lens', 'check security', plan))
          .to include("Review written to `docs/plans/x/REVIEW-001.md`.\n\n" \
                      "**Lens:** <the lens in one sentence>\n\n**Summary:**")
      end
  ```

- Change nothing else in the file.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. On line 20, append a
clause to the existing `planner review` line, before the `(default model opus)` part, for
example:

```
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it, then summarise it in the session under the same headings; `--lens` narrows the review, `--lens -` reads the lens from stdin (default model `opus`).
```

## Verification

1. `bundle exec rake` passes: all specs, including the new examples, plus RuboCop with no
   offences.
2. Render the prompt by hand. `Planner::Context` now also needs `home:` and `skills_dir:`;
   `Commands::Review` doesn't use them, so any `Pathname` will do. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def review(x, model:, report_file:) = puts(x, model, report_file); def default_review_model = "opus" }.new; Planner::Commands::Review.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' docs/plans/202610281426-add-review-sub-command/PLAN-002.md`
   The prompt ends with the "Summary for the user" section. Its fenced format starts with
   ``Review written to `docs/plans/202610281426-add-review-sub-command/REVIEW-002.md`.``,
   then one blank line, then `**Summary:**`. There is no `**Lens:**` line, no ERB leftovers
   and no stray blank lines. Run it again with `--lens -` appended and
   `echo "check security" |` in front. The `**Lens:**` line now appears between the
   `Review written to` line and `**Summary:**`, with one blank line either side.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib/planner/prompts/review.md.erb spec/planner/commands/review_spec.rb README.md docs/plans/202610281426-add-review-sub-command/ITERATION-002.md docs/plans/202610281426-add-review-sub-command/PLAN-002.md
```

This stages only the plan folder's `ITERATION-002.md` and `PLAN-002.md`; any `REVIEW-*.md`
files in the folder are left out. Write the message to a file and commit only the paths above:

```
git commit -F <file> -- lib/planner/prompts/review.md.erb spec/planner/commands/review_spec.rb README.md docs/plans/202610281426-add-review-sub-command/ITERATION-002.md docs/plans/202610281426-add-review-sub-command/PLAN-002.md
```

Suggested message:

```
Give the planner review summary a fixed format

The in-session summary came out in a different shape each run. The
review prompt now gives an exact format that mirrors the report
headings, lists every finding as a one-liner with its file:line, and
adds a Lens line when a lens is given.
```
