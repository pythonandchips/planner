# PLAN-001 — Make `planner run` tell the agent to follow the plan exactly

`planner run` currently passes the plan file's text to the agent unchanged, and agents have
strayed from plans or made their own decisions. This change wraps the plan in a fixed prompt,
an ERB template at `lib/planner/prompts/run.md.erb`. The prompt tells the agent to follow the
plan exactly, to treat its decisions as final, and to take the literal reading of anything
ambiguous. When a step can't be done, or a Verification step fails in a way the plan doesn't
cover, the agent stops without committing and explains in plain English what happened.
`Commands::Run` renders the template and hands the result to the agent. Also in scope: run
specs, one README line and one TODO bullet. File-name validation for `run` stays out of scope.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Command | `planner run` (the brief's "`plan run`") |
| How the instruction reaches the agent | An ERB template, `lib/planner/prompts/run.md.erb`, that wraps the plan. The rendered text is the prompt passed to `agent.run`, the same way `plan.md.erb` works. The agent adapter doesn't change. |
| Template variables | `plan_file` (the path as given) and `plan` (the file's content, trailing newlines stripped as today) |
| Stop triggers | A step can't be done as written, or a Verification step fails and the fix would need something the plan doesn't specify |
| Ambiguous step / step that looks wrong | Not a stop. Take the most literal reading, or do it as written. Never deviate. |
| Work already done when stopping | Leave it in the working tree. Do not commit. |
| Stop report | Plain English: the step it stopped at, why, what it already did, what is still left |
| Prompt wording | Exactly the text in Implementation (the user approved the draft, plus a new rule 3) |
| `PLAN-<N>.md` name validation for `run` | Out of scope. The TODO bullet stays. |
| Docs | README (through `update-readme`) and one new TODO bullet. No glossary change. |
| Spec depth for the prompt | Key content checks, not an exact match (the same as PLAN-001 in `202610271252-improve-plan-command`) |

## Files to create / change

```
lib/planner/prompts/run.md.erb        new: the run prompt template
lib/planner/commands/run.rb           render the template, agent.run(prompt, model:)
spec/planner/commands/run_spec.rb     update the default-model example, add prompt content examples
README.md                             the `planner run` usage line
docs/TODO.md                          add the post-run plan check bullet
```

`planner.gemspec` already ships `lib/**/*.erb` and `lib/planner.rb` already requires `erb`, so
neither changes. Leave `lib/planner/agents/claude.rb` and `spec/spec_helper.rb` as they are.

## Implementation

### `lib/planner/prompts/run.md.erb`

Create it with exactly this content, ending in a single trailing newline:

~~~~markdown
# Run Plan

Implement the plan `<%= plan_file %>`, reproduced below.
Follow it exactly.

## Rules

1. Do every step the plan lists, in order, and nothing
   else. Do not add features, refactors, files or changes
   the plan does not ask for.
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

## Plan

<%= plan %>
~~~~

### `lib/planner/commands/run.rb`

Change the class comment and `call`, and add a `TEMPLATE` constant and a private `prompt`
method, following `Commands::Plan`:

```ruby
# Wraps a plan file in the run prompt and hands it to the agent to implement.
class Run
  TEMPLATE = File.expand_path('../prompts/run.md.erb', __dir__)

  def call(args)
    model = parse(args)
    raise UsageError if model.empty? || args.size != 1

    file = args.first
    raise Error, "#{file} does not exist" unless File.file?(file)

    @context.agent.run(prompt(file), model:)
  end

  private

  def prompt(file)
    plan = File.read(file).sub(/\n+\z/, '')
    ERB.new(File.read(TEMPLATE)).result_with_hash(plan_file: file, plan:)
  end

  # parse(args) unchanged
end
```

- Option parsing, usage errors and the missing-file error stay exactly as they are.
- `prompt` sits before `parse` in the private section. Keep `parse` and its comment as they are.

### `spec/planner/commands/run_spec.rb`

The `before` block stays as it is (`PLAN-001.md` containing `"line one\n\nline two\n\n\n"`).

- Replace the "uses the agent's default model" example. Check that `agent.calls.size` is 1,
  that `agent.calls.first.first` is `:run`, and that `agent.calls.first.last` is
  `'default-model'`.
- Add a `describe 'the prompt'` group (or several examples) that reads the prompt from
  `agent.calls.first[1]` after `command.call(['PLAN-001.md'])` and checks that:
  - it starts with `"# Run Plan\n"`
  - it contains ``"Implement the plan `PLAN-001.md`"`` and `'Follow it exactly.'`
  - it contains `'take the\n   most literal reading'` (rule 3) and `'Do not commit.'` (rule 4)
  - it contains `'what is still left to do'` (rule 5)
  - it ends with `"## Plan\n\nline one\n\nline two\n"`. That proves inner newlines are kept,
    trailing newlines are stripped, and the plan sits at the end.
  - it does not contain `'<%'`
- Every other example stays unchanged. The model examples use `agent.calls.first.last`, so
  they still pass.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Change only the `planner run` usage line so it
says the agent is told to follow the plan file exactly and to stop and explain if it can't
finish it, for example:

```
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file exactly, stopping to explain if it can't (default model `sonnet`).
```

### `docs/TODO.md`

Add this bullet at the end:

```
- After `planner run`, check that the agent followed the plan (for example, compare the diff against the plan's file list).
```

## Verification

1. `bundle exec rake` passes: all specs, including the updated `run_spec`, plus RuboCop with
   no offences.
2. Render the prompt by hand and read it. From the repo root:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def run(x, model:) = puts(x); def default_run_model = "sonnet" }.new; Planner::Commands::Run.new(Planner::Context.new(root: Pathname.pwd, agent: a, stdout: $stdout, clock: -> { Time.now })).call(["docs/plans/202610271623-stop-run-straying-from-plan/PLAN-001.md"])'`
   The output starts with `# Run Plan`, names
   `` `docs/plans/202610271623-stop-run-straying-from-plan/PLAN-001.md` ``, shows rules 1 to 5,
   then `## Plan` followed by this plan's text. There are no ERB leftovers.
3. `bundle exec rake install` succeeds, and `gem contents planner` lists
   `lib/planner/prompts/run.md.erb`.
4. Running `planner run <plan-file>` against a real `claude` session is a manual smoke check
   for the user. The agent does not run it.

## Commit

Commit only after you have done everything in Implementation and every Verification step
passes. Run each git command as its own Bash call:

```
git add lib/planner/prompts/run.md.erb lib/planner/commands/run.rb spec/planner/commands/run_spec.rb README.md docs/TODO.md docs/plans/202610271623-stop-run-straying-from-plan
```

That last path stages this folder's `ITERATION-001.md` and `PLAN-001.md`. Write the message to
a file and commit with `git commit -F <file>`. Suggested message:

```
Tell the agent to follow the plan exactly in planner run

Wrap the plan file in a prompt template that makes the plan's steps
and decisions binding, takes the literal reading of anything
ambiguous, and has the agent stop without committing and explain in
plain English when a step can't be done or verification fails in a
way the plan doesn't cover.
```
