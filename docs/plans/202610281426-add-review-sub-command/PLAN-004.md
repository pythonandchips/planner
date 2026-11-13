# PLAN-004 — Let planner review run over FINDINGS files

`planner review` accepts only `PLAN-<N>.md` today. This change lets it also review a
`FINDINGS-<N>.md` file, or a lettered one such as `FINDINGS-<N>-a.md`, written by
`planner explore`. A findings review uses a new prompt template,
`lib/planner/prompts/review_findings.md.erb`, with "findings" wording and a findings checklist.
Its report goes in the same `REVIEW-<NNN>.md` series as plan reviews and takes the next free
letter suffix. The session can apply suggestions to the findings file the same way it can to a
plan. The agent's `plan_file:` keyword becomes `source_file:`. Also in scope: specs, the README
and the glossary. Everything PLAN-001 to PLAN-003 settled still applies to plan reviews: the
plan template's wording, the report headings, the summary format, lens handling, tool list and
table of contents handling don't change.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Findings names accepted | `FINDINGS-<N>.md` and lettered `FINDINGS-<N>-<letters>.md` (`-a`, `-b` … `-aa`). Plans stay `PLAN-<N>.md` only. |
| Report name for a findings review | The shared `REVIEW-<NNN>.md` series, using the findings number. If a plan review already took the name, use the first free letter suffix, as today. `FINDINGS-001-a.md` → `REVIEW-001.md` (or the next free suffix). |
| Applying suggestions to findings | Yes, same as plans. The findings file write is auto-approved. |
| What a findings reviewer reads | The findings file and the codebase only. Not the `ITERATION-<N>.md` brief or any other file in the plan folder. |
| No-lens checklist for findings | A separate five-point findings checklist (text in Implementation) |
| Templates | Two templates. `review.md.erb` stays for plans. The new `review_findings.md.erb` is for findings and duplicates the shared sections. |
| Template wording | Exactly the `review_findings.md.erb` text in Implementation (the user approved the draft) |
| Agent interface | Rename `plan_file:` to `source_file:` in `Agents::Claude#review`, `FakeAgent#review` and the template locals of both templates |
| Usage line | `planner review [--model <model>] [--lens <text>|-] <file>` |
| Bad-name error | `<file> is not a PLAN-<N>.md or FINDINGS-<N>.md file`. Still raised before the existence check. |
| Docs | README `planner review` line (through `update-readme`) and the glossary "review file" entry. No TODO change. |
| Specs | Key-string checks, same depth as PLAN-001 to PLAN-003 |
| Verification | `bundle exec rake` only |
| Commit | Yes |

## Files to create / change

```
lib/planner/prompts/review_findings.md.erb   new: the findings review prompt
lib/planner/prompts/review.md.erb            plan_file local renamed to source_file
lib/planner/commands/review.rb               accept FINDINGS files, choose the template
lib/planner/agents/claude.rb                 review takes source_file: instead of plan_file:
lib/planner/cli.rb                           usage line: <plan-file> → <file>
spec/spec_helper.rb                          FakeAgent#review takes source_file:
spec/planner/agents/claude_spec.rb           review example uses source_file:
spec/planner/commands/review_spec.rb         new error text, findings examples
README.md                                    planner review line
docs/GLOSSARY.md                             review file entry
```

`planner.gemspec` already ships `lib/**/*.erb`, so it doesn't change.

## Implementation

### `lib/planner/prompts/review.md.erb`

Replace every `<%= plan_file %>` with `<%= source_file %>`. There are four: the opening line,
rule 2, and two in "Applying suggestions". Change nothing else. The rendered text is identical.

### `lib/planner/prompts/review_findings.md.erb`

Create it with exactly this content, ending in a single trailing newline. Like
`review.md.erb`, it uses `-%>` tags and is rendered with `trim_mode: '-'`. The inner fences are
plain three-backtick fences inside the template.

~~~~markdown
# Review Findings

Review the findings `<%= source_file %>` and write
the review to `<%= review_file %>`. Read the
findings, then read the parts of the codebase they
touch and check the findings against them. Do not
read other files in the plan folder, except to update
the table of contents as described under "Table of
contents". Never use them to inform the review.

## Rules

1. Do not modify repository files, except the
   findings and the table of contents as described
   under "Applying suggestions" and "Table of
   contents".
2. You may write only `<%= review_file %>`,
   `<%= source_file %>` when the user asks you to
   apply suggestions, and `<%= toc_file %>` as
   described under "Table of contents".
3. Use read-only exploration only.
4. Focus on concrete findings with evidence.
5. Include file paths and line numbers where applicable.
6. Separate high-confidence findings from lower-confidence
   concerns.
7. Write in plain English.

## Focus

<% if lens -%>
Review the findings only through the lens below. Leave
out anything outside it.

<%= lens %>
<% else -%>
Check that:

1. The findings' claims match the code: the
   files, methods and line references they name
   exist and say what the findings say they do.
2. Every question under `## Questions` is
   answered.
3. The recommendations follow from the evidence.
4. Nothing is ambiguous enough that a reader
   would have to ask a question.
5. The findings do not miss risks or
   alternatives.
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

After writing `<%= review_file %>`, update
`<%= toc_file %>` as described under "Table of
contents".

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

## Applying suggestions

If the user asks you to apply suggestions from the
review, edit `<%= source_file %>` to make only those
changes. Then update `<%= review_file %>`: under
each finding, concern or recommendation you
applied, add the line

**Applied:** <what changed in the findings, in one line>

Change nothing else in the review. Then update
`<%= toc_file %>` as described under "Table of
contents". Then reply here in exactly this format:

```
Applied to `<%= source_file %>` and marked in
`<%= review_file %>`:
- <the item in one line>: <what changed in the findings>
```

## Table of contents

<%= table_of_content %>
~~~~

The lens wording ("Review the findings only through the lens below. Leave out anything outside
it.") is the plan template's lens sentence with "the plan" changed to "the findings", rewrapped.

### `lib/planner/commands/review.rb`

- Change the class comment to `# Renders the review prompt for a plan or findings file and
  hands it to the agent.`
- Replace `TEMPLATE` and `PLAN_NAME` with:

  ```ruby
  PLAN_TEMPLATE = File.expand_path('../prompts/review.md.erb', __dir__)
  FINDINGS_TEMPLATE = File.expand_path('../prompts/review_findings.md.erb', __dir__)
  # The files that can be reviewed. The plan number is in group 1, the findings number in group 2.
  SOURCE_NAME = /\A(?:PLAN-(\d+)|FINDINGS-(\d+)(?:-[a-z]+)?)\.md\z/
  ```

- Change `call` and the private methods so that:
  - the name check matches `File.basename(file)` against `SOURCE_NAME` and, on no match,
    raises `Error, "#{file} is not a PLAN-<N>.md or FINDINGS-<N>.md file"`. This stays before
    the existence check.
  - the number is `match[1] || match[2]`.
  - the template is `PLAN_TEMPLATE` when `match[1]` is set, otherwise `FINDINGS_TEMPLATE`.
  - `review_file(file, number)` is unchanged, so both kinds share the `REVIEW-<NNN>` series.
  - `prompt` takes the template and renders it with
    `ERB.new(File.read(template), trim_mode: '-').result_with_hash(source_file: file, review_file:, lens:, title:, toc_file: …, table_of_content: …)`.
    `title` and the table-of-contents values are built as today.
  - the agent call is
    `@context.agent.review(prompt, model:, report_file: review_file, source_file: file, toc_file: TableOfContent.path(File.dirname(file)))`.
  - stdin is still read only after the usage, name and existence checks pass.

  A shape that fits:

  ```ruby
  def call(args)
    model, lens = parse(args)
    raise UsageError if model.empty? || args.size != 1

    file = args.first
    match = File.basename(file).match(SOURCE_NAME)
    raise Error, "#{file} is not a PLAN-<N>.md or FINDINGS-<N>.md file" unless match
    raise Error, "#{file} does not exist" unless File.file?(file)

    template = match[1] ? PLAN_TEMPLATE : FINDINGS_TEMPLATE
    run_review(file, match[1] || match[2], template, model, read_lens(lens))
  end
  ```

  If RuboCop objects to the layout (for example `Metrics/AbcSize`, `Metrics/MethodLength` or
  `Metrics/ParameterLists`), reshape the code to satisfy it. The behaviour above must stay the
  same.

### `lib/planner/agents/claude.rb`

Replace `review` with:

```ruby
      def review(prompt, model:, report_file:, source_file:, toc_file:)
        @executor.call('claude', '--model', model, "--tools=#{REVIEW_TOOLS}",
                       "--allowedTools=Edit(#{report_file}),Edit(#{source_file}),Edit(#{toc_file})", prompt)
      end
```

The flags passed to `claude` don't change. The class comment and constants don't change.

### `lib/planner/cli.rb`

In `USAGE`, change the review line to:

```
       planner review [--model <model>] [--lens <text>|-] <file>
```

### Specs

- `spec/spec_helper.rb`, `FakeAgent`: change `review` to

  ```ruby
    def review(prompt, model:, report_file:, source_file:, toc_file:)
      @calls << [:review, prompt, model, report_file, source_file, toc_file]
    end
  ```

- `spec/planner/agents/claude_spec.rb`: in the "reviews with the given model, read-only tools
  and only the report and plan writable" example, change `plan_file: 'd/PLAN-001.md'` to
  `source_file: 'd/PLAN-001.md'`. The expected call doesn't change. Change nothing else.
- `spec/planner/commands/review_spec.rb`:
  - In `describe 'errors'`, change the expected message in "rejects a file that is not a
    PLAN-<N>.md file" to `'docs/plans/x/notes.md is not a PLAN-<N>.md or FINDINGS-<N>.md file'`
    and in "checks the name before the existence" to
    `'nope.md is not a PLAN-<N>.md or FINDINGS-<N>.md file'`. Rename the first example to
    "rejects a file that is not a plan or findings file".
  - Add `it 'rejects a lettered plan file'`: write `docs/plans/x/PLAN-001-a.md`, and calling
    with it raises `Error, 'docs/plans/x/PLAN-001-a.md is not a PLAN-<N>.md or FINDINGS-<N>.md file'`.
  - Add `describe 'a findings file'`, with `let(:findings) { 'docs/plans/x/FINDINGS-001.md' }`
    and a `before` that writes it. Examples:
    - "passes the findings file to the agent": `command.call([findings])` gives `call[0]`
      `:review`, `call[3]` `'docs/plans/x/REVIEW-001.md'`, `call[4]`
      `'docs/plans/x/FINDINGS-001.md'` and `call[5]` `'docs/plans/x/TABLE-OF-CONTENT.md'`.
    - "shares the REVIEW series with the plan": with `docs/plans/x/REVIEW-001.md` present,
      `call[3]` is `'docs/plans/x/REVIEW-001-a.md'`.
    - "accepts a lettered findings file": write `docs/plans/x/FINDINGS-002-aa.md`; calling with
      it gives `call[3]` `'docs/plans/x/REVIEW-002.md'` and `call[4]`
      `'docs/plans/x/FINDINGS-002-aa.md'`.
    - "uses the findings prompt": the prompt (`call[1]`) starts with `"# Review Findings\n"`,
      contains ``'Review the findings `docs/plans/x/FINDINGS-001.md`'``,
      ``'`# REVIEW-001 — docs/plans/x/FINDINGS-001.md`'``, `'Every question under `## Questions`'`,
      `'edit `docs/plans/x/FINDINGS-001.md` to make only those'` and
      `'**Applied:** <what changed in the findings, in one line>'`, and does not contain
      `'# Review Plan'`, `'## Lens'` or `'<%'`.
    - "narrows a findings review to the lens": with `--lens 'check security'`, the prompt
      contains `'Review the findings only through the lens below'`, `"check security\n"` and
      ``'`## Lens`'``, and does not contain `'Check that:'`.
    - "reports a missing findings file": `docs/plans/x/FINDINGS-009.md` (missing) raises
      `Error, 'docs/plans/x/FINDINGS-009.md does not exist'`.
  - Change nothing else in the file. If RuboCop objects to an example's length or wrapping
    (`RSpec/ExampleLength`, `Layout/LineLength`), split or rewrap it. The checks must stay the
    same.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. On the existing
`planner review` line, change `<plan-file>` to `<file>` and say it reviews a plan or findings
file. For example:

```
- `planner review [--model <model>] [--lens <text>|-] <file>`: have the agent review a `PLAN-<N>.md` or `FINDINGS-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it, then summarise it in the session under the same headings; `--lens` narrows the review, `--lens -` reads the lens from stdin; ask in the session and it applies suggestions to the reviewed file and marks each one `**Applied:**` in the review (default model `opus`).
```

### `docs/GLOSSARY.md`

Replace the "review file" entry with:

```
- **review file**: `REVIEW-<NNN>.md`, or `REVIEW-<NNN>-<letter>.md` for a later review with the same number. A plain-English review of a plan or findings file, written by `planner review`. When the user has the review session apply suggestions to the reviewed file, each applied item gets an `**Applied:**` line.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new and changed examples, plus RuboCop
   with no offences.

## Commit

Commit only after you have done everything in Implementation and the Verification step
passes. Run each git command as its own Bash call:

```
git add lib spec README.md docs/GLOSSARY.md docs/plans/202610281426-add-review-sub-command/ITERATION-004.md docs/plans/202610281426-add-review-sub-command/PLAN-004.md
```

This folder has no `TABLE-OF-CONTENT.md`, so there is none to stage. Leave out any `REVIEW-*.md`
files and the untracked files in `docs/plans/202611050909-convert-skills-to-rubocop-config/`.
Write the message to a file in the scratchpad directory, then commit only the paths above:

```
git commit -F <file> -- lib spec README.md docs/GLOSSARY.md docs/plans/202610281426-add-review-sub-command/ITERATION-004.md docs/plans/202610281426-add-review-sub-command/PLAN-004.md
```

Suggested message. Follow the `commit-message` skill for the trailer:

```
Let planner review run over FINDINGS files

planner review now accepts a FINDINGS-<N>.md file, or a lettered one,
as well as a PLAN-<N>.md file. Findings get their own prompt with a
findings checklist, share the REVIEW-<NNN> series with plan reviews,
and can have suggestions applied like a plan. The agent's plan_file:
keyword becomes source_file:.
```

## Deviations

- RuboCop `Metrics/AbcSize` and `Layout/LineLength` failed on `Commands::Review#call` and `run_review` because the plan's shape was too long; changed `lib/planner/commands/review.rb` to move the name and existence checks into a private `source_match` method and build `toc_file` in a local variable
- RuboCop `RSpec/ExampleLength` failed on the "uses the findings prompt" example because it had nine lines; changed `spec/planner/commands/review_spec.rb` to split it into three examples under `describe 'the findings prompt'` with the same checks, using a `prompt` helper method instead of `let` to stay under `RSpec/MultipleMemoizedHelpers`

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-13T16:17:50Z |
| Finished | 2026-11-13T16:18:52Z |
| Elapsed | 1m 2s |
| Model | sonnet |
| Tokens | ~60k (estimate) |
