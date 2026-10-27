# PLAN-001 — Bundle the plan-from-iteration instructions into `planner plan`

`planner plan` currently runs `claude` with `/plan-from-iteration <file>`, so it depends on a
separately installed skill. This change moves those instructions into the gem as an ERB
template, `lib/planner/prompts/plan.md.erb`. `Commands::Plan` renders the template with the
iteration file, its folder and the target plan file, then hands the rendered text to the agent
as the initial prompt. The command also starts rejecting files that aren't named
`ITERATION-<digits>.md`, because the plan file name is derived from that number. Also in
scope: deleting `docs/examples/plan-from-iteration-skill.md`, and updating the TODO, glossary
and README.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Where the instructions live | An ERB template file at `lib/planner/prompts/plan.md.erb` |
| Templating | ERB (stdlib), rendered with `result_with_hash` |
| Template variables | `iteration_file` (the path as given), `folder` and `plan_file` |
| Path form for `folder` / `plan_file` | Relative to the given path: `folder = File.dirname(file)`, `plan_file = File.join(folder, "PLAN-NNN.md")` |
| How claude receives it | As the initial prompt: `claude --model opus "<rendered prompt>"` (an interactive session, the same shape as `run`) |
| Who builds the prompt | `Commands::Plan`. The agent interface becomes `plan(prompt)` and stays a thin wrapper. |
| Adapting the skill text | Light. Drop the YAML frontmatter. Replace step 1 ("identify the iteration file") with the concrete paths. Reword "skill" as "these instructions". Keep everything else word for word. |
| Non-`ITERATION-<digits>.md` file name | Raise `Error, "<file> is not an ITERATION-<N>.md file"` (exit 1) |
| Check order | Name check first, then the existence check |
| Plan number | Zero-padded to 3 digits: `ITERATION-3.md` and `ITERATION-003.md` both give `PLAN-003.md` |
| `docs/examples/plan-from-iteration-skill.md` | Delete it |
| `~/.claude/skills/plan-from-iteration` (installed copy) | Leave it alone. The plan does not touch or mention it beyond this row. |
| `docs/TODO.md` | Remove the "Bundle the skill" bullet. Reduce the "validate file names" bullet to `run` only. |
| Glossary | The plan file is "written … by `planner plan`" |
| README | Update with the `update-readme` skill |
| Spec depth for the prompt | Key content checks, not an exact match |

## Files to create / change

```
lib/planner/prompts/plan.md.erb        new: the prompt template
lib/planner/commands/plan.rb           validate name, render template, agent.plan(prompt)
lib/planner/agents/claude.rb           plan(prompt) passes the prompt straight through
lib/planner.rb                         require 'erb'
planner.gemspec                        ship lib/**/*.erb
spec/spec_helper.rb                    FakeAgent#plan(prompt)
spec/planner/commands/plan_spec.rb     rewrite for the new behaviour
spec/planner/agents/claude_spec.rb     update the plan example
spec/exe/planner_spec.rb               update the missing-file smoke spec
docs/examples/plan-from-iteration-skill.md   delete
docs/TODO.md
docs/GLOSSARY.md
README.md
```

## Implementation

### `lib/planner/prompts/plan.md.erb`

Create it with exactly this content (it's the skill body, adapted as decided):

~~~~markdown
# Plan From Iteration

Turn the requirements doc `<%= iteration_file %>` into an implementation plan
`<%= plan_file %>`. Both live in the plan folder `<%= folder %>/`.

## Steps

1. **Read the whole folder, not just the one file.** Read `<%= iteration_file %>`,
   plus every other `ITERATION-*.md` and `PLAN-*.md` already in `<%= folder %>/`. Earlier
   plans record decisions that still apply. Treat them as established context, not
   something to ask about again.
2. **Resolve every open question before writing anything.** Do not assume a requirement,
   guess at a default, or fill a gap silently. Read the iteration file and list every
   decision point it leaves open, then ask the user about all of them together. Keep
   iterating (ask follow-ups, refine, ask again) until nothing is left ambiguous. Only
   once every question has an explicit answer do you move on to drafting the plan.
3. **Write `<%= plan_file %>`.** Follow the structure below. Keep it concise and
   unambiguous. A developer should be able to execute it without needing to ask a
   follow-up question.
4. **End the plan with a Commit section.** State exactly what to stage and give a
   suggested commit message, with the instruction that the commit happens only after the
   plan's change has actually been made (implemented and verified), never before.

## Plan structure

Match the convention already used by `PLAN-*.md` files elsewhere in `docs/plans/`:

```markdown
# PLAN-<N> — <short title>

<One paragraph: what this change is and its scope.>

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| <each question you resolved with the user, one row per decision> | <the answer> |

## Files to create / change

<concrete file list or diff-shaped description>

## Implementation

<the plan itself, in as much concrete detail as the decisions support>

## Verification

<how to confirm the change works: tests to run, commands to execute>

## Commit

<what to stage and a suggested commit message, contingent on verification passing>
```

The "Decisions" table records every question you asked and how the user answered it.
It lets a future iteration in the same folder skip asking again about things that are
already settled.

## Notes

- Never make a decision on the user's behalf, even a small one. Surface it as a
  question instead. This is the one rule these instructions exist to enforce.
- Check sibling files in the folder for precedent before asking a question that was
  already answered there.
~~~~

### `lib/planner/commands/plan.rb`

```ruby
# Renders the plan prompt for an iteration file and hands it to the agent.
class Plan
  TEMPLATE = File.expand_path('../prompts/plan.md.erb', __dir__)
  ITERATION_NAME = /\AITERATION-(\d+)\.md\z/

  def call(args)
    file = args.first
    raise UsageError if file.nil? || file.empty?

    number = File.basename(file)[ITERATION_NAME, 1] or
      raise Error, "#{file} is not an ITERATION-<N>.md file"
    raise Error, "#{file} does not exist" unless File.file?(file)

    @context.agent.plan(prompt(file, number))
  end

  private

  def prompt(file, number)
    folder = File.dirname(file)
    plan_file = File.join(folder, format('PLAN-%03d.md', number.to_i))
    ERB.new(File.read(TEMPLATE)).result_with_hash(iteration_file: file, folder:, plan_file:)
  end
end
```

- Extra args are still ignored. `UsageError` for a nil or empty file is unchanged.
- `File.join('docs/plans/x', 'PLAN-001.md')` gives `docs/plans/x/PLAN-001.md`. A bare
  `ITERATION-1.md` gives folder `.` and plan file `./PLAN-001.md`. That's acceptable; don't
  special-case it.
- Write the class to match the existing style (`initialize(context)` unchanged). If RuboCop
  objects to the `or raise` form, use a plain `unless`/`raise`. The behaviour must stay
  the same.

### `lib/planner/agents/claude.rb`

- `def plan(prompt) = @executor.call('claude', '--model', PLAN_MODEL, prompt)`. Write it in
  the file's existing multi-line `def` style.
- The class comment stays the same (the interface is still `#plan`, `#run`,
  `#default_run_model`).

### Other code

- `lib/planner.rb`: add `require 'erb'` alongside the other stdlib requires.
- `planner.gemspec`: `spec.files = Dir['lib/**/*.rb', 'lib/**/*.erb', 'exe/*', 'README.md']`.
- `spec/spec_helper.rb`: rename the `FakeAgent#plan` parameter to `prompt`. It records
  `[:plan, prompt]`.

### Specs

- `spec/planner/commands/plan_spec.rb`, written in a tmp dir:
  - `docs/plans/x/ITERATION-001.md` exists. The agent receives exactly one
    `[:plan, prompt]` call. The prompt starts with `"# Plan From Iteration\n"`, contains
    `docs/plans/x/ITERATION-001.md`, `docs/plans/x/` and `docs/plans/x/PLAN-001.md`, and
    does not contain `<%`.
  - `docs/plans/x/ITERATION-3.md` gives a prompt containing `docs/plans/x/PLAN-003.md`.
  - No args raises `UsageError`.
  - `docs/plans/x/ITERATION-009.md` (missing) raises
    `Error, 'docs/plans/x/ITERATION-009.md does not exist'`.
  - `notes.md` (existing file, bad name) raises `Error, 'notes.md is not an ITERATION-<N>.md file'`.
  - `nope.md` (missing *and* bad name) raises the name error, which proves name-first ordering.
- `spec/planner/agents/claude_spec.rb`: rename the plan example to "plans with opus using
  the given prompt". `agent.plan('do the plan')` gives
  `[['claude', '--model', 'opus', 'do the plan']]`.
- `spec/exe/planner_spec.rb`: the missing-file smoke spec runs `planner('plan', 'ITERATION-001.md')`
  and expects exit 1 and `"[planner] ITERATION-001.md does not exist\n"`.

### Docs

- Delete `docs/examples/plan-from-iteration-skill.md`.
- `docs/TODO.md`:
  - Remove the "Bundle the `plan-from-iteration` skill …" bullet.
  - Change "Validate the file names passed to `plan` (`ITERATION-*.md`) and `run` (`PLAN-*.md`)."
    to "Validate the file name passed to `run` (`PLAN-*.md`)."
- `docs/GLOSSARY.md`: plan file definition: "The implementation plan written from an
  iteration file by `planner plan`."
- `README.md`: follow `.claude/skills/update-readme/SKILL.md`. Keep the edit small. The
  `planner plan` line should make clear that it takes an `ITERATION-<N>.md` file and the
  agent writes the matching `PLAN-<N>.md` next to it. Don't mention the old skill.

## Verification

1. `bundle exec rake` passes: all specs, including the ones above, plus RuboCop with no offences.
2. Render the prompt by hand and check that it reads correctly, with no ERB leftovers. From
   the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, agent: a, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271252-improve-plan-command/ITERATION-001.md"])'`
   The output names `…/ITERATION-001.md`, `…/202610271252-improve-plan-command/` and
   `…/PLAN-001.md`.
3. `bundle exec rake install` succeeds, then:
   - `planner plan README.md` exits 1 with `[planner] README.md is not an ITERATION-<N>.md file`.
   - `gem contents planner` lists `lib/planner/prompts/plan.md.erb`.
4. Running `planner plan <iteration-file>` against a real `claude` session is a manual smoke
   check for the user. The agent does not run it.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib planner.gemspec spec docs README.md
```

`git add docs` stages the deletion of `docs/examples/plan-from-iteration-skill.md` and also
this folder's `ITERATION-001.md` and `PLAN-001.md`. Write the message to a file and commit
with `git commit -F <file>`. Suggested message:

```
Bundle plan-from-iteration instructions into planner plan

Render the planning instructions from an ERB template shipped with
the gem and hand them to the agent as the initial prompt, instead of
relying on a separately installed /plan-from-iteration skill. The
command now rejects files not named ITERATION-<N>.md and tells the
agent the exact PLAN-<NNN>.md path to write.
```
