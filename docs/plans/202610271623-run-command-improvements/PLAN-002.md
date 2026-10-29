# PLAN-002 — Have `planner run` prepend a run summary to the plan

`planner run` doesn't record that a plan has been run. This change extends the run prompt
(`lib/planner/prompts/run.md.erb`) so the agent writes a "Run summary" section at the very top
of the plan file, both when it finishes and when it stops. The summary has the status, the start
and finish times, the elapsed time, the model, an estimate of tokens used, and a table of every
command the agent couldn't run unassisted, so permissions or instructions can be added later. The
agent measures everything itself. Planner keeps `exec`ing an interactive `claude` session and only
adds the model to the template. Also in scope: run specs, the README run line, and removing the
matching TODO bullet.

## Decisions (resolved, do not revisit)

PLAN-001's decisions still apply: the ERB template, the `plan_file` and `plan` variables, the stop
rules, not committing on a stop, and key-content spec checks rather than an exact match.

| Decision | Choice |
| --- | --- |
| How time and tokens are measured | The agent reports them itself. This is a prompt-only change: `exec` and the interactive session stay. |
| Start time | The agent runs `date -u +%Y-%m-%dT%H:%M:%SZ` before anything else. It runs the same command again for the finish time. |
| Tokens | The agent's best estimate, labelled `(estimate)` |
| When the summary is written | Always: on a full run (Status `Completed`) and on a stop (Status `Stopped`) |
| Order on a full run | After every Verification step passes and before the Commit step. The plan file is staged with the commit even if the plan's Commit section doesn't list it. |
| Order on a stop | Write the summary but still don't commit (PLAN-001 rule 4) |
| Commands that count as "unable to run unassisted" | Ones that needed a permission prompt, ones denied by permissions or blocked by the sandbox, ones handed to the user to run, and ones that failed and had to be run again in another form |
| Summary layout | `## Run summary` heading, a Field/Value table, a `### Commands that needed help` table (Command / What happened / Suggested fix), then `---` |
| Field rows | Status, Started, Finished, Elapsed, Model, Tokens. Add Stopped at and Reason only when Status is `Stopped`. |
| Model row | Planner passes the model into the template as a new `model` variable |
| No commands needed help | Leave out the `### Commands that needed help` heading and table |
| Existing summary / re-runs | Not handled. A plan isn't resumed in another session. A run the user cancels writes nothing. |
| Prompt wording | Exactly the text in Implementation (the user approved the draft) |
| Docs | Update the README `planner run` line (through `update-readme`). Remove the matching `docs/TODO.md` bullet. |

## Files to create / change

```
lib/planner/prompts/run.md.erb        add the start-time line, change rule 1, add rule 6 and the Run summary section
lib/planner/commands/run.rb           pass model: into the template
spec/planner/commands/run_spec.rb     add prompt content examples for the summary
README.md                             the `planner run` usage line
docs/TODO.md                          remove the "mark the plan as implemented" bullet
```

`lib/planner/agents/claude.rb`, `spec/spec_helper.rb` and `planner.gemspec` don't change.

## Implementation

### `lib/planner/prompts/run.md.erb`

Replace the whole file with exactly this content, ending in a single trailing newline:

~~~~markdown
# Run Plan

Implement the plan `<%= plan_file %>`, reproduced below.
Follow it exactly.

Before anything else, run `date -u +%Y-%m-%dT%H:%M:%SZ`
and keep the output as the start time.

## Rules

1. Do every step the plan lists, in order, and nothing
   else apart from the run summary below. Do not add
   features, refactors, files or changes the plan does
   not ask for.
2. The plan's decisions are final. Do not substitute a
   different approach, library, name or wording, even if
   you think another would be better.
3. If a step can be read more than one way, take the
   most literal reading. If a step looks wrong, do it as
   written anyway. Do not stop or deviate for either.
4. Stop as soon as a step cannot be done as written, or a
   Verification step fails and fixing it would need
   something the plan does not specify. Do not work around
   it. Do not commit. Leave the changes made so far in
   place.
5. When you stop, tell the user in plain English:
   - the step you stopped at
   - why it could not be completed
   - what you have already done
   - what is still left to do
6. Write the run summary when you finish and when you
   stop. When you finish, write it after every
   Verification step passes and before the Commit step,
   and stage `<%= plan_file %>` with the commit even if
   the Commit section does not list it. When you stop,
   write it but still do not commit.

## Run summary

As you go, keep a list of every command you could not
run unassisted: commands that needed the user to approve
a permission prompt, commands denied by permissions or
blocked by the sandbox, commands you asked the user to
run, and commands that failed and had to be run again in
another form.

To write the summary, run `date -u +%Y-%m-%dT%H:%M:%SZ`
for the finish time. Then add the following to the very
top of `<%= plan_file %>`, above everything already
there, and change nothing else in that file:

```
## Run summary

| Field | Value |
| --- | --- |
| Status | Completed or Stopped |
| Started | <start time> |
| Finished | <finish time> |
| Elapsed | <finish minus start, e.g. 17m 29s> |
| Model | <%= model %> |
| Tokens | <best estimate of tokens used, e.g. ~85k> (estimate) |
| Stopped at | <the step you stopped at> |
| Reason | <one sentence on why> |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `<command>` | <what happened> | <the permission or instruction that would let it run unassisted> |

---

```

- Include the Stopped at and Reason rows only when
  Status is Stopped.
- Leave out the Commands that needed help heading and
  table when there were none.

## Plan

<%= plan %>
~~~~

Rules 2 to 5 are unchanged from today's file.

### `lib/planner/commands/run.rb`

Pass the model through to the template. Change only these lines:

```ruby
@context.agent.run(prompt(file, model), model:)
```

```ruby
def prompt(file, model)
  plan = File.read(file).sub(/\n+\z/, '')
  ERB.new(File.read(TEMPLATE)).result_with_hash(plan_file: file, plan:, model:)
end
```

Everything else in the file, including the class comment, stays as it is.

### `spec/planner/commands/run_spec.rb`

Add these examples inside the existing `describe 'the prompt'` group. Its `prompt` `let` already
runs `command.call(['PLAN-001.md'])`, so the model is `'default-model'`:

- `it 'asks for the start time before anything else'`: the prompt includes
  ``"Before anything else, run `date -u +%Y-%m-%dT%H:%M:%SZ`"``.
- `it 'writes the summary on finish and on stop, staging the plan file'`: the prompt includes
  `'6. Write the run summary when you finish and when you'` and
  ``"stage `PLAN-001.md` with the commit"``.
- `it 'prepends the summary to the plan file'`: the prompt includes
  ``"top of `PLAN-001.md`, above everything already"`` and `"## Run summary\n\n| Field | Value |"`.
- `it 'fills in the model and asks for a labelled token estimate'`: the prompt includes
  `'| Model | default-model |'` and `'(estimate) |'`.
- `it 'lists commands that needed help'`: the prompt includes
  `"### Commands that needed help\n\n| Command | What happened | Suggested fix |"`.

Add one example outside that group, after `it 'accepts the model after the file'`:

```ruby
it 'puts the chosen model in the run summary' do
  command.call(['-m', 'x', 'PLAN-001.md'])

  expect(agent.calls.first[1]).to include('| Model | x |')
end
```

Every existing example stays unchanged. `ends with the plan` and `leaves no ERB tags behind` still
apply to the new template.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Change only the `planner run` usage line (line 19)
to:

```
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file exactly, stopping to explain if it can't, and prepend a run summary (status, elapsed time, estimated tokens, commands that needed help) to the plan file (default model `sonnet`).
```

### `docs/TODO.md`

Remove this bullet and leave the others as they are:

```
- Add an instruction to run to mark the plan as implemented once complete
```

## Verification

1. `bundle exec rake` passes: all specs, including the new `run_spec` examples, plus RuboCop with
   no offences.
2. Render the prompt by hand and read it. From the repo root:
   `ruby -Ilib -rplanner -rstringio -e 'a = Struct.new(:p) { def run(x, model:) = puts(x); def default_run_model = "sonnet" }.new; Planner::Commands::Run.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: StringIO.new, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271623-run-command-improvements/PLAN-002.md"])'`
   The output starts with `# Run Plan`, then the start-time line, rules 1 to 6, the `## Run summary`
   instructions with `| Model | sonnet |`, then `## Plan` followed by this plan's text. There are no
   ERB leftovers.
3. Running `planner run <plan-file>` against a real `claude` session, and checking the summary it
   prepends, is a manual smoke check for the user. The agent does not run it.

## Commit

Commit only after you have done everything in Implementation and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/prompts/run.md.erb lib/planner/commands/run.rb spec/planner/commands/run_spec.rb README.md docs/TODO.md docs/plans/202610271623-run-command-improvements
```

That last path stages this folder's `ITERATION-002.md` and `PLAN-002.md`, including any run
summary prepended to `PLAN-002.md`. Write the message to a file and commit with
`git commit -F <file>`. Suggested message:

```
Have planner run prepend a run summary to the plan

Extend the run prompt so the agent writes a Run summary at the top of
the plan file when it finishes or stops: status, start and finish
times, elapsed time, model, an estimate of tokens used, and the
commands it couldn't run unassisted, with a suggested fix for each.
The plan file is staged with the plan's commit.
```
