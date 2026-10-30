# PLAN-003 — Open the findings file with a summary and recommendations

Make `planner explore` write a `## Summary` and a `## Recommendations` section at the top of
the findings file, after the title and before `## Questions`. The summary is the same content
as the session reply: one or two sentences, then every finding as a numbered one-liner. The
findings in `## Findings` are numbered `### 1.`, `### 2.` … to match. Recommendations are
advisory: further exploration or actions a later iteration could plan, each ending with the
finding(s) it follows from. The prompt's "Do not recommend a course of action." is removed,
which reverses that part of PLAN-001's findings-sections decision. The session reply gains a
`**Recommendations:**` list and numbers its findings. In scope: the explore prompt template,
its specs, the GLOSSARY and the README explore bullet. `plan.md.erb`, the command code and
the agent are not changed. Everything else PLAN-001 and PLAN-002 decided still applies.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Placement | `## Summary` then `## Recommendations`, both straight after the `# <title>` line and before `## Questions`. Order: Summary, Recommendations, Questions, Decisions, Findings, then the stats |
| Summary form | Same content as the session reply: one or two sentences, then every finding as a numbered one-liner |
| Summary shape in the file | Sentence(s), blank line, numbered list `1. <file:line or URL where there is one>: <finding in one line>`. No bold labels |
| Finding numbering | `## Findings` uses `### 1. <short title>`, `### 2. …` subheadings. The summary list and the session reply's `**Findings:**` list are numbered to match |
| Recommendations grouping | One bullet list, not split into exploration vs actions |
| Recommendations heading | Plain `## Recommendations`. "Advisory" is stated only in the prompt and the glossary |
| Recommendation citation | Each ends with the finding(s) it follows from: `(finding 2)` or `(findings 2, 3)` |
| No recommendations | The section stays, with the single line `None.` (same in the session reply) |
| "Do not recommend a course of action." | Removed from the prompt |
| Session reply | Keeps its format, numbers the `**Findings:**` list, and adds a `**Recommendations:**` bullet list after it |
| `plan.md.erb` reading FINDINGS / recommendations | Out of scope, as PLAN-001 decided |
| Prompt wording | Exactly the text in Implementation (the user approved the draft) |
| Docs | GLOSSARY: reword **summary**, add **recommendations**, extend **findings file**. README: extend the explore bullet (via `update-readme`). All worded as in Implementation (the user approved the draft). The review file's own `## Summary` is not mentioned in the glossary |
| Specs | Update the existing `explore_spec.rb` prompt examples that the new text breaks, and add one example for the top of the findings structure |
| Plan folder files in the commit | `ITERATION-003.md`, `PLAN-003.md`, and `REVIEW-003.md` if one exists by then |

## Files to change

```
lib/planner/prompts/explore.md.erb       findings structure block and session reply
spec/planner/commands/explore_spec.rb    three examples changed, one added
docs/GLOSSARY.md                         summary reworded, recommendations added, findings file extended
README.md                                explore usage bullet
```

## Implementation

### `lib/planner/prompts/explore.md.erb`

Make exactly these two replacements. Everything else in the file stays as it is. Inner fences
are plain three-backtick fences, as now.

1. **Findings structure.** Replace everything from the ` ```markdown ` line under
   `## Findings structure` (currently line 52) through the line
   `model. Do not recommend a course of action.` (currently line 72) with:

   ~~~~
   ```markdown
   # <%= title %> — <short title>

   ## Summary

   <one or two sentences answering the brief>

   1. <file:line or URL where there is one>: <finding 1 in one line>

   ## Recommendations

   - <further exploration, or an action a later iteration could plan> (finding <N>)

   ## Questions

   <the questions the brief asks, numbered>

   ## Decisions (resolved, do not revisit)

   | Decision | Choice |
   | --- | --- |
   | <each question you resolved with the user> | <the answer> |

   ## Findings

   ### 1. <short title>

   <what you found, with evidence>
   ```

   Number the findings `### 1.`, `### 2.` and so on.
   List every finding in the Summary, one line each,
   under the same number.

   Recommendations are advisory: further exploration, or
   actions a later iteration could plan. Nothing in them
   has been decided. End each one with the finding or
   findings it follows from, such as `(finding 2)` or
   `(findings 2, 3)`. Write `None.` when you have none.

   Use mermaid diagrams where a picture makes a finding
   clearer, such as a flow, a dependency graph or a data
   model.
   ~~~~

2. **Summary for the user.** Replace everything from the opening ` ``` ` fence under
   `plain-English summary in exactly this format:` (currently line 112) to the end of the
   file (currently line 121, `List every finding, one line each.`) with the text below. The
   file still ends with a single trailing newline.

   ~~~~
   ```
   Findings written to `<%= findings_file %>`.

   **Summary:** <one or two sentences>

   **Findings:**
   1. <file:line or URL where there is one>: <the finding in one line>

   **Recommendations:**
   - <the recommendation in one line> (finding <N>)
   ```

   List every finding and every recommendation, one line
   each, numbered and worded as in the file. Write `None.`
   under Recommendations when there are none.
   ~~~~

### `spec/planner/commands/explore_spec.rb`

All changes are in `describe 'the prompt'`.

1. In "reads FINDINGS files and has the findings sections", drop
   `'Do not recommend a course of action.'` so it reads:

   ```ruby
       it 'reads FINDINGS files and has the findings sections' do
         expect(prompt).to include('`FINDINGS-*.md`', '## Questions', '## Decisions (resolved, do not revisit)',
                                   '## Findings', 'mermaid')
       end
   ```

2. Straight after that example, add:

   ```ruby
       it 'opens the findings with the summary and recommendations' do # rubocop:disable RSpec/ExampleLength
         expect(prompt).to include(
           "# FINDINGS-001 — <short title>\n\n## Summary\n\n<one or two sentences answering the brief>\n\n" \
           "1. <file:line or URL where there is one>: <finding 1 in one line>\n\n## Recommendations\n\n" \
           "- <further exploration, or an action a later iteration could plan> (finding <N>)\n\n## Questions",
           '### 1. <short title>', 'Recommendations are advisory', 'Write `None.` when you have none.'
         )
         expect(prompt).not_to include('Do not recommend a course of action.')
       end
   ```

3. Replace the "has the summary format" example with:

   ```ruby
       it 'has the summary format' do
         expect(prompt).to include('## Summary for the user',
                                   "Findings written to `docs/plans/x/FINDINGS-001.md`.\n\n**Summary:**",
                                   "**Findings:**\n1. <file:line",
                                   "**Recommendations:**\n- <the recommendation in one line> (finding <N>)",
                                   'List every finding and every recommendation, one line')
       end
   ```

4. In "allows web fetches for what the repository cannot answer", change
   `'- <file:line or URL where there is one>: <the finding in one line>'` to
   `'1. <file:line or URL where there is one>: <the finding in one line>'`. Nothing else in
   that example changes.

Each single-quoted string sits on one line of the template. The double-quoted strings with
`\n` match consecutive template lines exactly as written in the replacements above.

### `docs/GLOSSARY.md`

1. Replace the **summary** entry with this one line:

   ```
   - **summary**: The plain-English account of what the agent found. `planner explore` writes it as `## Summary` at the top of the findings file, and after `planner explore` or `planner review` writes its file the agent also gives one in the session.
   ```

2. Straight after it, add this one line:

   ```
   - **recommendations**: The `## Recommendations` section near the top of a findings file: further exploration, or actions a later iteration could plan, each citing the findings it follows from. Advisory only: nothing in it has been decided.
   ```

3. In the **findings file** entry, after `found by exploring the code, data or web pages.` add
   ` It opens with a summary and recommendations.` The entry then reads:

   ```
   - **findings file**: `FINDINGS-<NNN>.md`, or `FINDINGS-<NNN>-<letter>.md` for a later exploration of the same iteration. Answers to the questions in an iteration file, found by exploring the code, data or web pages. It opens with a summary and recommendations. Written by `planner explore`, and never executed.
   ```

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Replace the `planner explore` bullet in Usage
with this one line:

```
- `planner explore [--model <model>] <iteration-file>`: have the agent answer an `ITERATION-<N>.md` brief by exploring the code or data, asking you about anything unclear, and write a read-only `FINDINGS-<N>.md` next to it that opens with a summary and advisory recommendations, then summarise it in the session (default model `opus`).
```

## Verification

1. `bundle exec rake` passes: all specs, including the changed and new ones, plus RuboCop with
   no offences.
2. Render the prompt by hand from the repo root, with a fake agent that prints its arguments:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def explore(x, model:, findings_file:) = puts(x, model, findings_file); def default_explore_model = "opus" }.new; Planner::Commands::Explore.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- docs/plans/202610291422-add-explore-task-to-planner/ITERATION-003.md`
   In the output, the findings structure runs `# FINDINGS-003 — <short title>`, `## Summary`,
   `## Recommendations`, `## Questions`, `## Decisions (resolved, do not revisit)`,
   `## Findings`, `### 1. <short title>` in that order. `Do not recommend a course of action.`
   does not appear. The session reply block has `**Findings:**` followed by a `1. ` line and a
   `**Recommendations:**` list. There are no ERB leftovers, and the last two lines are `opus`
   and `docs/plans/202610291422-add-explore-task-to-planner/FINDINGS-003.md`.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call. Stage:

```
git add lib/planner/prompts/explore.md.erb spec/planner/commands/explore_spec.rb docs/GLOSSARY.md README.md docs/plans/202610291422-add-explore-task-to-planner/ITERATION-003.md docs/plans/202610291422-add-explore-task-to-planner/PLAN-003.md
```

If `docs/plans/202610291422-add-explore-task-to-planner/REVIEW-003.md` exists, stage it too
with its own `git add`.

Write the message to a file and commit with `git commit -F <file>`. The message follows the
`commit-message` skill's rules: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Open explore findings with a summary and recommendations

A findings file now starts with a summary of every finding and a list
of advisory recommendations: further exploration, or actions a later
iteration could plan. Findings are numbered so each recommendation can
cite the ones it follows from, and the session reply lists the
recommendations too. The prompt no longer forbids recommending.

The glossary and README describe the new sections.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-30T16:05:09Z |
| Finished | 2026-10-30T16:05:33Z |
| Elapsed | 24s |
| Model | sonnet |
| Tokens | ~30k (estimate) |
