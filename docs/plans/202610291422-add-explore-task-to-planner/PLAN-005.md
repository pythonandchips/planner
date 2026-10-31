# PLAN-005 — Make `planner explore` conversational

Turn the explore agent's single ask-then-write pass into a loop inside one interactive session.
The loop is: clarify the brief if it needs it, explore, ask about what the exploration turned up,
investigate further, rewrite the findings file, then check in with a summary and suggested next
steps. The user then picks a step, names a focus, says continue or says finish, and the agent
goes back to asking until they finish. On finish the agent rewrites the file a final time, adds
the stats and gives the existing final reply. In scope: the explore prompt template, its specs,
the README explore bullet and the GLOSSARY **findings file** entry. The command code, the agent
and the CLI are not changed. This replaces PLAN-001's "when the agent asks questions" decision
(ask everything up front and write nothing until all are answered). Everything else PLAN-001 to
PLAN-004 decided still applies.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the loop lives | In the prompt only. Planner still execs one interactive `claude` session. No Ruby loop, no change to `Commands::Explore` or `Agents::Claude` |
| Questions before the first exploration | Allowed: the agent may ask to clarify the brief before it starts exploring |
| No questions after a round | Skip the ask step and go straight on to investigating further, writing and checking in |
| Findings file during the loop | One file, `FINDINGS-<NNN>.md` (suffix rules unchanged), rewritten whole each round in the full structure. No round log. No stats until finish |
| Check-in reply | `Findings so far written to …`, `**Summary:**`, `**Recommendations:**`, `**Next steps:**` (2-4 numbered directions the agent suggests), then a fixed line: pick a step by number, name a focus, say continue, or say finish |
| After the check-in | Any new focus is added to `## Questions`, and the agent goes back to the ask step |
| Finish | Rewrite the file a final time, append the stats once, then give the existing "Summary for the user" reply |
| `## Questions` section | The brief's questions, then each aspect the user asked to focus on, numbered |
| Commands that needed help | One list kept across every round, written once in the stats at finish |
| Prompt wording | Exactly the text in Implementation (the user approved the draft) |
| Docs | README explore bullet and GLOSSARY **findings file** entry, worded as in Implementation (the user approved the draft) |
| Specs | Add one `explore_spec.rb` prompt example for the loop. No existing example breaks |
| Plan folder files in the commit | `ITERATION-005.md`, `PLAN-005.md`, and `REVIEW-005.md` if one exists by then |

## Files to change

```
lib/planner/prompts/explore.md.erb       intro, steps, Questions placeholder, new Check-in section, stats timing, final reply trigger
spec/planner/commands/explore_spec.rb    one new prompt example
README.md                                explore usage bullet
docs/GLOSSARY.md                         findings file entry
```

## Implementation

### `lib/planner/prompts/explore.md.erb`

Make exactly these seven replacements. Everything else in the file stays as it is. Inner fences
are plain three-backtick fences, as now. The file still ends with a single trailing newline.

1. **Intro.** After the line `nothing in them will be executed.` (currently line 8) and its
   following blank line, insert this paragraph and a blank line, so it sits before `## Rules`:

   ```
   The exploration is a conversation. Explore in rounds,
   rewrite the findings file after each round, and check
   in with the user, until the user tells you to finish.
   ```

2. **Steps 2 to 5.** Replace everything from `2. **Resolve every open question before writing`
   (currently line 27) through `   "Summary for the user".` (currently line 48) with:

   ```
   2. **Clarify the brief.** If the brief is unclear, ask
      the user about it before you start exploring. Do
      not assume what the brief wants answered, guess at
      scope, or fill a gap silently.
   3. **Explore.** Start with the repository. Fetch web
      pages only for what it cannot answer, such as how a
      framework or library behaves. You cannot search the
      web: fetch URLs from the brief, the code, gem
      metadata or ones you know, and ask the user for a
      URL when you cannot find one. Back every finding
      with evidence: file paths and line numbers, the
      data you read, or the URL you fetched.
   4. **Ask.** List every decision point the exploration
      turned up and ask the user about all of them
      together. Keep asking until nothing is ambiguous.
      If you have no questions, go straight on to step 5.
   5. **Investigate further** based on the answers. If a
      question cannot be answered from what you can read,
      ask the user how to proceed.
   6. **Write `<%= findings_file %>`** in the structure
      below, covering everything found so far. Rewrite
      the whole file each round. Do not add the stats
      yet.
   7. **Check in** with the user in the format under
      "Check-in". If they pick a next step, name an
      aspect to focus on, or say continue, add any new
      focus to `## Questions` and go back to step 4.
   8. **Finish** when the user tells you to: rewrite
      `<%= findings_file %>` a final time, add the stats,
      and reply in the format under "Summary for the
      user".
   ```

3. **Questions placeholder.** In the findings structure, replace
   `<the questions the brief asks, numbered>` with
   `<the questions the brief asks, then each aspect the user asked you to focus on, numbered>`.

4. **Check-in section.** After the line `model.` that ends the mermaid paragraph (currently
   line 91) and its blank line, insert this section and a blank line, so it sits before
   `## Stats`:

   ~~~~
   ## Check-in

   After each round's write, reply here in exactly this
   format, then wait for the user:

   ```
   Findings so far written to `<%= findings_file %>`.

   **Summary:** <the Summary paragraph from the file>

   **Recommendations:**
   - <the recommendation in one line> (finding <N>)

   **Next steps:**
   1. <a direction to explore next, in one line>

   Pick a next step by number, name an aspect to focus
   on, say continue to keep on the current path, or say
   finish to write the final findings.
   ```

   List every recommendation as in the file, and two to
   four next steps. Write `None.` under Recommendations
   when there are none.
   ~~~~

5. **Command list across rounds.** In the Stats section, change the line `another form.`
   (currently line 100) to `another form. Keep it across every round.`

6. **Stats timing.** Straight after that line's paragraph (before the blank line and
   `Add the following to the very end of`), insert a blank line and this paragraph:

   ```
   Add the stats only once, when the user tells you to
   finish.
   ```

   The `Add the following to the very end of` paragraph and the stats block below it are not
   changed.

7. **Final reply trigger.** Under `## Summary for the user`, replace

   ```
   When the file is written, reply here with a
   plain-English summary in exactly this format:
   ```

   with

   ```
   When the user tells you to finish and the final file
   is written, reply here with a plain-English summary in
   exactly this format:
   ```

   The reply block and the lines after it are not changed.

After the edits, the Steps section reads steps 1 (unchanged) to 8 as above, and the section order
is: intro, conversation paragraph, `## Rules`, `## Steps`, `## Findings structure`,
`## Check-in`, `## Stats`, `## Summary for the user`.

### `spec/planner/commands/explore_spec.rb`

In `describe 'the prompt'`, straight before the "has the stats with the model" example, add:

```ruby
    it 'runs the exploration as a conversation' do # rubocop:disable RSpec/ExampleLength
      expect(prompt).to include(
        'The exploration is a conversation.', '2. **Clarify the brief.**', '4. **Ask.**',
        'If you have no questions, go straight on to step 5.', 'the whole file each round.',
        '7. **Check in**', '8. **Finish** when the user tells you to:', "## Check-in\n\nAfter each round's write",
        "Findings so far written to `docs/plans/x/FINDINGS-001.md`.\n\n**Summary:**",
        "**Next steps:**\n1. <a direction to explore next, in one line>",
        'Add the stats only once, when the user tells you to', 'then each aspect the user asked you to focus on'
      )
      expect(prompt).not_to include('Resolve every open question before writing')
    end
```

No other example changes: every string the existing examples check is still in the template,
and the check-in's `Findings so far written to` does not contain `Findings written to`.
This example and the rest of the explore specs were run against the drafted template while
writing this plan: 21 examples, 0 failures.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Replace the `planner explore` bullet in Usage
with this one line:

```
- `planner explore [--model <model>] <iteration-file>`: have the agent answer an `ITERATION-<N>.md` brief by exploring the code or data in rounds, asking you about anything unclear and checking in after each round so you can steer it or finish, and write a read-only `FINDINGS-<N>.md` next to it that opens with a summary and advisory recommendations, then summarise it in the session (default model `opus`).
```

### `docs/GLOSSARY.md`

In the **findings file** entry, after `It opens with a summary and recommendations.` add
` It is rewritten after each round of exploration, and gets its stats when you finish.` The
entry then reads:

```
- **findings file**: `FINDINGS-<NNN>.md`, or `FINDINGS-<NNN>-<letter>.md` for a later exploration of the same iteration. Answers to the questions in an iteration file, found by exploring the code, data or web pages. It opens with a summary and recommendations. It is rewritten after each round of exploration, and gets its stats when you finish. Written by `planner explore`, and never executed.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new one, plus RuboCop with no offences.
2. Render the prompt by hand from the repo root, with a fake agent that prints its arguments:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def explore(x, model:, findings_file:) = puts(x, model, findings_file); def default_explore_model = "opus" }.new; Planner::Commands::Explore.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- docs/plans/202610291422-add-explore-task-to-planner/ITERATION-005.md`
   In the output:
   - `The exploration is a conversation.` comes straight before `## Rules`.
   - Steps are numbered 1 to 8 with the bold leads Read the whole folder, Clarify the brief,
     Explore, Ask, Investigate further, Write, Check in, Finish. `Resolve every open question`
     does not appear.
   - The sections run `## Findings structure`, `## Check-in`, `## Stats`,
     `## Summary for the user`. The check-in block names
     `docs/plans/202610291422-add-explore-task-to-planner/FINDINGS-005.md` and has
     `**Next steps:**` followed by a `1. ` line.
   - There are no ERB leftovers, and the last two lines are `opus` and
     `docs/plans/202610291422-add-explore-task-to-planner/FINDINGS-005.md`.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call. Stage:

```
git add lib/planner/prompts/explore.md.erb spec/planner/commands/explore_spec.rb README.md docs/GLOSSARY.md docs/plans/202610291422-add-explore-task-to-planner/ITERATION-005.md docs/plans/202610291422-add-explore-task-to-planner/PLAN-005.md
```

If `docs/plans/202610291422-add-explore-task-to-planner/REVIEW-005.md` exists, stage it too
with its own `git add`.

Write the message to a file and commit with `git commit -F <file>`. The message follows the
`commit-message` skill's rules: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Make planner explore conversational

The explore agent used to ask every question up front and write the
findings once. It now works in rounds: it explores, asks about what it
found, investigates further, rewrites the findings file and checks in
with a summary and suggested next steps. You can pick a step, name a
new focus, carry on or finish. The stats and the final summary are
written only when you finish.

The README and glossary describe the rounds.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-31T14:07:05Z |
| Finished | 2026-10-31T14:07:42Z |
| Elapsed | 37s |
| Model | sonnet |
| Tokens | ~40k (estimate) |
