# PLAN-004 — Add `--print` to `planner run` for a software factory

A software factory needs to run planner's run prompt through its own `claude` command. This
change adds a `-p` / `--print` option to `planner run`. With it, planner builds exactly the prompt
plain `planner run` would send, then writes it to stdout as pretty-printed JSON with the model
and a hard-coded list of the tools a run needs. It does not launch the agent. The tool list lives
on `Agents::Claude` as `RUN_TOOLS`, exposed through a new `run_tools` method. Plain `planner run`
is unchanged. Also in scope: run and agent specs, `FakeAgent`, the CLI usage text and the README
run line. The run prompt template (`lib/planner/prompts/run.md.erb`) does not change.

## Decisions (resolved, do not revisit)

PLAN-001's to PLAN-003's decisions still apply: the ERB run template and its variables, the rules,
the deviations and stats, and key-content spec checks rather than an exact prompt match.

| Decision | Choice |
| --- | --- |
| Flags | `-p` and `--print`, no argument. They can be combined with `-m` / `--model` and go before or after the file, like `-m`. |
| Output format | Valid JSON from `JSON.pretty_generate`, followed by one newline, written to the context's stdout |
| Keys and order | `prompt`, `model`, `allowedTools` |
| `prompt` value | The exact text plain `planner run` would pass to the agent for the same arguments |
| `model` value | The `--model` value, or the agent's default run model (`sonnet`). The same value as the prompt's Stats `Model` row. |
| `allowedTools` value | The hard-coded list `["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Skill"]` |
| Where the list lives | `Agents::Claude::RUN_TOOLS = %w[Bash Read Edit Write Glob Grep Skill].freeze`, returned by a new `run_tools` method. `FakeAgent#run_tools` returns `%w[Tool]`. `Commands::Run` asks the agent for it. |
| Agent call with `--print` | None. `agent.run` is not called and no `claude` process is started. |
| Validation with `--print` | The same as today: the same `UsageError`s and the same missing-file `Error` |
| Plain `planner run` | Unchanged. It does not pass `--allowedTools` to `claude`. |
| Docs | The README `planner run` line (through `update-readme`) and the run line in `CLI::USAGE`. No TODO or glossary change. |
| Spec coverage | run_spec: `-p` and `--print` each print parseable JSON with the keys in order; the printed prompt equals what plain run sends; the model honours `-m` and defaults to the agent's default; the agent is not called; the missing-file error is still raised. claude_spec: a `run_tools` example. |

## Files to create / change

```
lib/planner.rb                         require 'json'
lib/planner/agents/claude.rb           add RUN_TOOLS and run_tools, add #run_tools to the class comment
lib/planner/commands/run.rb            parse -p/--print, print JSON instead of running
lib/planner/cli.rb                     the run line in USAGE
spec/spec_helper.rb                    FakeAgent#run_tools
spec/planner/agents/claude_spec.rb     run_tools example
spec/planner/commands/run_spec.rb      a describe '--print' group
README.md                              the `planner run` usage line
```

`lib/planner/prompts/run.md.erb`, `lib/planner/table_of_content.rb` and `planner.gemspec` don't
change.

## Implementation

### 1. `lib/planner.rb`

Add `require 'json'` between `require 'fileutils'` and `require 'optparse'`.

### 2. `lib/planner/agents/claude.rb`

- In the class comment, change `(#plan, #run, #review, ...` to `(#plan, #run, #run_tools, #review, ...`.
  Rewrap the comment so no line passes 120 characters; keep the rest of its wording.
- Add this constant straight after `DEFAULT_RUN_MODEL = 'sonnet'`:

  ```ruby
  RUN_TOOLS = %w[Bash Read Edit Write Glob Grep Skill].freeze
  ```

- Add this method straight after `default_run_model`:

  ```ruby
  def run_tools
    RUN_TOOLS
  end
  ```

`run` stays exactly as it is.

### 3. `lib/planner/commands/run.rb`

Replace the class comment, `call` and `parse`, and add a private `print_json` method before
`prompt`. `prompt` stays as it is.

```ruby
# Wraps a plan file in the run prompt and hands it to the agent to implement, or prints it as JSON.
class Run
  TEMPLATE = File.expand_path('../prompts/run.md.erb', __dir__)

  def initialize(context)
    @context = context
  end

  def call(args)
    model, print_only = parse(args)
    raise UsageError if model.empty? || args.size != 1

    file = args.first
    raise Error, "#{file} does not exist" unless File.file?(file)

    text = prompt(file, model)
    return print_json(text, model) if print_only

    @context.agent.run(text, model:)
  end

  private

  def print_json(text, model)
    @context.stdout.puts JSON.pretty_generate(prompt: text, model:, allowedTools: @context.agent.run_tools)
  end

  # prompt(file, model) unchanged

  # Removes the options from args and returns the chosen model and whether to print instead of run.
  def parse(args)
    model = @context.agent.default_run_model
    print_only = false
    OptionParser.new do |opts|
      opts.on('-m', '--model MODEL') { |value| model = value }
      opts.on('-p', '--print') { print_only = true }
    end.parse!(args)
    [model, print_only]
  rescue OptionParser::ParseError
    raise UsageError
  end
end
```

### 4. `lib/planner/cli.rb`

Change the run line in `USAGE` to:

```
       planner run [--model <model>] [--print] <plan-file>
```

Keep its leading spaces aligned with the other lines.

### 5. `spec/spec_helper.rb`

Add this method to `FakeAgent` straight after `default_run_model`:

```ruby
def run_tools
  %w[Tool]
end
```

### 6. `spec/planner/agents/claude_spec.rb`

Add this example straight after `it 'defaults the run model to sonnet'`:

```ruby
it 'lists the tools a run needs' do
  expect(agent.run_tools).to eq(%w[Bash Read Edit Write Glob Grep Skill])
end
```

### 7. `spec/planner/commands/run_spec.rb`

Follow the `writing-rspec` skill. Add this group straight after `it 'raises Error for a missing file'`.
Every other example stays unchanged.

```ruby
describe '--print' do
  let(:output) { JSON.parse(context.stdout.string) }

  %w[-p --print].each do |flag|
    it "prints the prompt, model and allowed tools as JSON for #{flag}" do
      command.call([flag, 'PLAN-001.md'])

      expect(output.keys).to eq(%w[prompt model allowedTools])
      expect(output['allowedTools']).to eq(%w[Tool])
    end
  end

  it 'pretty-prints the JSON' do
    command.call(['-p', 'PLAN-001.md'])

    expect(context.stdout.string).to start_with("{\n  \"prompt\": ")
    expect(context.stdout.string).to end_with("}\n")
  end

  it 'prints the prompt plain run sends' do
    command.call(['-p', 'PLAN-001.md'])
    command.call(['PLAN-001.md'])

    expect(output['prompt']).to eq(agent.calls.first[1])
  end

  it "prints the agent's default model" do
    command.call(['--print', 'PLAN-001.md'])

    expect(output['model']).to eq('default-model')
  end

  it 'prints the chosen model' do
    command.call(['PLAN-001.md', '-p', '-m', 'x'])

    expect(output['model']).to eq('x')
    expect(output['prompt']).to include('| Model | x |')
  end

  it 'does not start the agent' do
    command.call(['-p', 'PLAN-001.md'])

    expect(agent.calls).to be_empty
  end

  it 'raises Error for a missing file' do
    expect { command.call(['-p', 'nope.md']) }.to raise_error(Planner::Error, 'nope.md does not exist')
  end
end
```

### 8. `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. Change only the `planner run` usage line (line 19)
to:

```
- `planner run [--model <model>] [--print] <plan-file>`: have the agent implement a plan file exactly, fixing failing verification steps and stopping to explain if it can't, and append deviations and stats to the plan file (default model `sonnet`); `--print` (`-p`) prints the prompt, model and allowed tools as JSON instead, for running with your own `claude` command.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new `run_spec` and `claude_spec` examples,
   plus RuboCop with no offences.
2. Print the JSON by hand and read it. From the repo root:
   `ruby -Ilib -rplanner -rstringio -e 'Planner::Commands::Run.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: Planner::Agents::Claude.new, stdin: StringIO.new, stdout: $stdout, clock: -> { Time.now })).call(["--print", "docs/plans/202610271623-run-command-improvements/PLAN-004.md"])'`
   The output is a JSON object with `prompt`, `model` and `allowedTools` in that order. `prompt`
   starts with `# Run Plan` and ends with this plan's text, `model` is `"sonnet"`, and
   `allowedTools` is `["Bash", "Read", "Edit", "Write", "Glob", "Grep", "Skill"]`. No `claude`
   process starts.
3. Piping that output into a factory's own `claude` command is a manual smoke check for the user.
   The agent does not run it.

Do not run `bundle exec rake install`. It writes outside the repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes. Run
each git command as its own Bash call:

```
git add lib/planner.rb lib/planner/agents/claude.rb lib/planner/commands/run.rb lib/planner/cli.rb spec/spec_helper.rb spec/planner/agents/claude_spec.rb spec/planner/commands/run_spec.rb README.md docs/plans/202610271623-run-command-improvements/ITERATION-004.md docs/plans/202610271623-run-command-improvements/PLAN-004.md
```

Write the message to a file in `$TMPDIR` and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Add --print to planner run for running the prompt elsewhere

A software factory needs to run planner's run prompt through its own
claude command. planner run --print (or -p) now writes the prompt it
would send, the model and the tools a run needs to stdout as JSON,
and doesn't start the agent. The tool list is hard-coded on the
Claude agent for now. Plain planner run is unchanged.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-04T17:37:15Z |
| Finished | 2026-11-04T17:37:42Z |
| Elapsed | 27s |
| Model | sonnet |
| Tokens | ~40k (estimate) |
