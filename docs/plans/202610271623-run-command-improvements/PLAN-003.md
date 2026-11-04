# PLAN-003 — Let `planner run` fix failing verification steps

The run prompt's rule 4 makes the agent stop as soon as a Verification step fails in a way the
plan doesn't cover, so runs stop on failing tests the agent could have fixed. This change edits
the run prompt (`lib/planner/prompts/run.md.erb`) so the agent investigates and fixes any failing
Verification step. It still stops when the failure comes from the environment, isn't caused by the
plan's changes, would need a fix that goes against a plan decision, or still fails after three
fixes. Each fix is recorded as a bullet in a new `## Deviations` section, which is appended to the
plan file just before the stats. Files changed by a fix are staged with the commit. This is a
prompt-only change: `lib/planner/commands/run.rb` doesn't change. Also in scope: run specs and the
README run line.

## Decisions (resolved, do not revisit)

PLAN-001's and PLAN-002's decisions still apply where this plan doesn't change them: the ERB
template, stopping without committing, the plain-English stop report, the stats, and key-content
spec checks rather than an exact match.

| Decision | Choice |
| --- | --- |
| Which failures the agent may fix | Any failing Verification step (specs, RuboCop, anything else), unless one of the stop cases below applies |
| What a fix may change | Code and specs, including specs the plan gives word for word |
| Environment failures (stop, don't fix) | Can't connect to a database or other service; a sandbox or permission denial; a missing command, gem or package; a missing environment variable, secret or config file |
| Failures not caused by the plan's changes (including ones already failing) | Stop and report. The agent decides this from its own investigation. There is no baseline run beforehand. |
| Other stop cases | The fix would go against one of the plan's decisions, or the same failure still fails after three fixes |
| Steps that can't be done as written (not Verification) | Unchanged: stop (rule 4) |
| How fixes are recorded | A `## Deviations` section appended to the end of the plan file just before the stats' `---`, one bullet per fix (what failed, the cause, the files changed and what the fix did). Written on finish and on stop. Left out when nothing was fixed. |
| Environment stops | Reported to the user in the rule 6 stop report. Stats are written as for any other stop, including the "Commands that needed help" row where it applies. There is no extra environment-specific section. |
| Files changed by a fix that the Commit section doesn't list | Staged with the commit, like the plan file |
| Rule numbering | Rule 4 is split, the new rule 5 is fix-and-stop, and the old rules 5 and 6 become 6 and 7 |
| Prompt wording | Exactly the text in Implementation (the user approved the draft) |
| Docs | Only the README `planner run` line, with the shorter wording in Implementation. No TODO change. |

## Files to create / change

```
lib/planner/prompts/run.md.erb        rewrite rules 1 and 4, add rule 5, renumber 5 and 6 to 6 and 7, rewrite rule 7, add the Deviations section
spec/planner/commands/run_spec.rb     update the rule 7 example, add examples for rule 5 and Deviations
README.md                             the `planner run` usage line
```

`lib/planner/commands/run.rb`, `lib/planner/table_of_content.rb`, `lib/planner/agents/claude.rb`
and `planner.gemspec` don't change.

## Implementation

### 1. `lib/planner/prompts/run.md.erb`

Replace the whole `## Rules` section, from the `## Rules` line up to the blank line before
`## Stats`, with exactly this text. Then insert the `## Deviations` section shown below it between
the rules and `## Stats`, with one blank line before and after. Everything else in the file stays
exactly as it is: the heading, the intro, the start-time line, `## Stats`, `## Table of contents`
and `## Plan`.

~~~~markdown
## Rules

1. Do every step the plan lists, in order, and nothing
   else apart from fixes under rule 5, the deviations,
   the stats and the table of contents below. Do not
   add features, refactors, files or changes the plan
   does not ask for.
2. The plan's decisions are final. Do not substitute a
   different approach, library, name or wording, even if
   you think another would be better.
3. If a step can be read more than one way, take the
   most literal reading. If a step looks wrong, do it as
   written anyway. Do not stop or deviate for either.
4. Stop as soon as a step cannot be done as written.
   Do not work around it. Do not commit. Leave the
   changes made so far in place.
5. If a Verification step fails, investigate and fix
   it. You may change code and specs, including specs
   the plan gives word for word. Stop instead, as in
   rule 4, when:
   - the failure comes from the environment: a
     database or other service you cannot connect to,
     a sandbox or permission denial, a missing command,
     gem or package, or a missing environment variable,
     secret or config file
   - the failure is not caused by the plan's changes
   - the fix would go against one of the plan's
     decisions
   - the same failure still fails after three fixes
6. When you stop, tell the user in plain English:
   - the step you stopped at
   - why it could not be completed
   - what you have already done
   - what is still left to do
7. Write the deviations, then the stats, when you
   finish and when you stop, then update the table of
   contents as described under "Table of contents".
   When you finish, do all three after every
   Verification step passes and before the Commit
   step, and stage `<%= plan_file %>` and every file
   you changed under rule 5 with the commit even if
   the Commit section does not list them, along with
   `<%= toc_file %>` if you updated it. When you
   stop, do all three but still do not commit.

## Deviations

If you fixed anything under rule 5, add the following
to the very end of `<%= plan_file %>`, before the
stats, one bullet per fix. Leave it out when you fixed
nothing.

```
## Deviations

- <what failed> failed because <cause>; changed
  <files> to <what the fix did>
```
~~~~

Rules 2, 3 and 6 have the same text as today's rules 2, 3 and 5.

### 2. `spec/planner/commands/run_spec.rb`

Inside `describe 'the prompt'`:

- Replace the example `it 'writes the stats on finish and on stop, staging the plan file'` with:

  ```ruby
  it 'writes the deviations and stats on finish and on stop, staging the plan file and fixed files' do
    expect(prompt).to include(
      '7. Write the deviations, then the stats, when you',
      'stage `PLAN-001.md` and every file'
    )
  end
  ```

- Add these examples after `it 'asks for a plain English report of what is left'`:

  ```ruby
  it 'fixes failing verification steps' do
    expect(prompt).to include('5. If a Verification step fails, investigate and fix',
                              'You may change code and specs, including specs')
  end

  it 'stops on environment failures' do
    expect(prompt).to include('- the failure comes from the environment: a',
                              'a sandbox or permission denial, a missing command,')
  end

  it 'stops on unrelated failures, fixes against a decision and repeated failures' do
    expect(prompt).to include("- the failure is not caused by the plan's changes",
                              "- the fix would go against one of the plan's",
                              '- the same failure still fails after three fixes')
  end

  it 'adds the deviations before the stats' do
    expect(prompt).to include('end of `PLAN-001.md`, before the',
                              "## Deviations\n\n- <what failed> failed because <cause>; changed")
  end
  ```

Every other example stays unchanged. `'Do not commit.'`, rule 3's
`"take the\n   most literal reading"`, `'what is still left to do'`, `'the stats and the table of'`
and `` '`./TABLE-OF-CONTENT.md` if you updated it' `` are all still in the new text. Use single
quotes for any string that has no `\n`, interpolation or apostrophe (RuboCop's default
`Style/StringLiterals`).

### 3. `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Change only the `planner run` usage line (line 19)
to:

```
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file exactly, fixing failing verification steps and stopping to explain if it can't, and append deviations and stats to the plan file (default model `sonnet`).
```

## Verification

1. `bundle exec rake` passes: all specs, including the new and changed `run_spec` examples, plus
   RuboCop with no offences.
2. Render the prompt by hand and read it. From the repo root:
   `ruby -Ilib -rplanner -rstringio -e 'a = Struct.new(:p) { def run(x, model:) = puts(x); def default_run_model = "sonnet" }.new; Planner::Commands::Run.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: StringIO.new, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271623-run-command-improvements/PLAN-003.md"])'`
   The output starts with `# Run Plan`, then the start-time line, rules 1 to 7 as written above,
   `## Deviations`, `## Stats` with `| Model | sonnet |`, `## Table of contents`, then `## Plan`
   followed by this plan's text. There are no ERB leftovers.
3. Running `planner run <plan-file>` against a real `claude` session, with a failing spec the agent
   should fix, is a manual smoke check for the user. The agent does not run it.

Do not run `bundle exec rake install`. It writes outside the repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes. Run
each git command as its own Bash call:

```
git add lib/planner/prompts/run.md.erb spec/planner/commands/run_spec.rb README.md docs/plans/202610271623-run-command-improvements/ITERATION-003.md docs/plans/202610271623-run-command-improvements/PLAN-003.md
```

Write the message to a file in `$TMPDIR` and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Let planner run fix failing verification steps

The run prompt made the agent stop on any failing Verification step
the plan didn't cover, so runs stopped on tests it could have fixed.
The agent now investigates and fixes the failure, changing code or
specs as needed. It still stops when the failure comes from the
environment, isn't caused by the plan's changes, would need a fix
that goes against a plan decision, or still fails after three fixes.

Each fix is recorded under a Deviations section appended to the plan
file before the stats, and files changed by a fix are staged with the
commit.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-04T10:03:41Z |
| Finished | 2026-11-04T10:04:02Z |
| Elapsed | 21s |
| Model | sonnet |
| Tokens | ~40k (estimate) |
