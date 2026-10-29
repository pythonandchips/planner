## Run summary

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-10-29T14:49:22Z |
| Finished | 2026-10-29T14:50:16Z |
| Elapsed | 0m 54s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `ruby -Ilib -rplanner -e '...' -- $M $F` (Verification step 3, run in a shell loop) | `-m sonnet` was passed as one argument under zsh, so the model came out as ` sonnet` and I re-ran it with the arguments written out | None needed; it was a quoting mistake in my loop, not a permission problem |

---

# PLAN-001 — Add a `planner explore` command

Add `planner explore [--model <model>] <iteration-file>`. It takes an `ITERATION-<N>.md` brief
and hands the agent a prompt to answer it by exploring the codebase or data. Before writing, the
agent resolves every open question with the user. It then writes a read-only
`FINDINGS-<N>.md` next to the brief. The file ends with a run summary, and the agent then
replies in the session with a fixed-format summary. Nothing in the findings is executed or
committed. In scope: the command, its prompt template, the Claude agent method, CLI wiring,
specs, and a README line and GLOSSARY entry. The `plan` prompt is not changed.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Input and output | `planner explore docs/plans/x/ITERATION-002.md` writes `docs/plans/x/FINDINGS-002.md` (number zero-padded to 3, as `plan` does) |
| Model | `--model` / `-m` option, default `opus` (as `review`) |
| Tools | Read-only, as `review`: `--tools=Read,Grep,Glob,Write` and `--allowedTools=Edit(<findings file>)`. No Bash |
| Findings file already exists | First free `FINDINGS-<NNN>-a.md`, `-b` … `-z`, `-aa` …, as `review` names REVIEW files |
| Findings file sections | `# <file basename> — <short title>`, `## Questions`, `## Decisions (resolved, do not revisit)`, `## Findings`, then the run summary. No Recommendation section; the prompt says not to recommend a course of action |
| Sibling files the agent reads | Every `ITERATION-*.md`, `PLAN-*.md` and `FINDINGS-*.md` in the folder, as established context |
| `plan` prompt reading FINDINGS files | Out of scope. `plan.md.erb` is not changed and no TODO line is added |
| Commit | The explore agent commits nothing |
| Mermaid | The prompt allows mermaid diagrams where a picture makes a finding clearer |
| When the agent asks questions | Up front, and again whenever exploring turns up a new decision point. Nothing is written until all are answered |
| Unanswerable question | The agent asks the user how to proceed before writing |
| Run summary placement | At the end of the findings file, after a `---` line |
| Run summary rows | `Model` and `Tokens (estimate)` only. No Status, Stopped at, Reason, Started, Finished or Elapsed rows (interactive command, always completes). Planner does not pass a start time |
| Help table | `### Tool calls that needed help` with columns Tool call / What happened / Suggested fix: calls that needed approval, were denied, or failed and were retried. Left out when there were none |
| Session reply | Fixed format: `Findings written to <file>.`, `**Summary:**`, `**Findings:**` bullets (every finding, one line, `file:line` first where there is one). No Status line |
| Prompt wording | Exactly the template text in Implementation (the user approved the draft) |
| Agent interface | `Agents::Claude#explore(prompt, model:, findings_file:)`, `#default_explore_model`, constants `DEFAULT_EXPLORE_MODEL = 'opus'` and `EXPLORE_TOOLS = 'Read,Grep,Glob,Write'` |
| CLI | `'explore' => Commands::Explore` after `'review'` in `COMMANDS`. Usage line `planner explore [--model <model>] <iteration-file>` after the review line |
| Errors | Same text as `plan`: `<file> is not an ITERATION-<N>.md file`, checked before `<file> does not exist` |
| Specs | `explore_spec.rb` at the same depth as `review_spec.rb`, plus Claude agent specs, one CLI dispatch spec and one `exe/planner` spec |
| Docs | A README usage bullet (via `update-readme`) and a GLOSSARY **findings file** entry, worded as in Implementation. No TODO change |
| Plan folder files in the commit | `ITERATION-001.md`, `PLAN-001.md` and `REVIEW-001.md` |

## Files to create / change

```
lib/planner/commands/explore.rb          new: the command
lib/planner/prompts/explore.md.erb       new: the prompt template
lib/planner/agents/claude.rb             add #explore, #default_explore_model, constants, interface comment
lib/planner/cli.rb                       register explore, add usage line
lib/planner.rb                           require the new command
spec/planner/commands/explore_spec.rb    new
spec/planner/agents/claude_spec.rb       two new examples
spec/planner/cli_spec.rb                 one new example
spec/exe/planner_spec.rb                 one new example
spec/spec_helper.rb                      FakeAgent#explore, #default_explore_model
README.md                                usage bullet
docs/GLOSSARY.md                         findings file entry
```

## Implementation

### `lib/planner/prompts/explore.md.erb` (new)

Put exactly this text in the file, ending in a single trailing newline. The inner fences are
plain three-backtick fences, as in `plan.md.erb`. There are no `<% %>` control tags, so the
template needs no `trim_mode`.

~~~~markdown
# Explore From Iteration

Answer the brief `<%= iteration_file %>` by exploring
the codebase or data, and write what you find to
`<%= findings_file %>`. Both live in the plan folder
`<%= folder %>/`. The findings are for reading only:
nothing in them will be executed.

## Rules

1. Do not modify repository files.
2. You may write only `<%= findings_file %>`.
3. Use read-only exploration only.

## Steps

1. **Read the whole folder, not just the one file.**
   Read `<%= iteration_file %>`, plus every other
   `ITERATION-*.md`, `PLAN-*.md` and `FINDINGS-*.md`
   already in `<%= folder %>/`. Earlier files record
   decisions that still apply. Treat them as
   established context, not something to ask about
   again.
2. **Resolve every open question before writing
   anything.** Do not assume what the brief wants
   answered, guess at scope, or fill a gap silently.
   List every decision point the brief leaves open and
   ask the user about all of them together. If
   exploring turns up a new decision point, ask about
   that too. Keep asking until nothing is ambiguous.
3. **Explore.** Back every finding with evidence:
   file paths and line numbers, or the data you read.
   If a question cannot be answered from what you can
   read, ask the user how to proceed before writing
   anything.
4. **Write `<%= findings_file %>`** in the structure
   below, ending with the run summary.
5. **Reply to the user** in the format under
   "Summary for the user".

## Findings structure

```markdown
# <%= title %> — <short title>

## Questions

<the questions the brief asks, numbered>

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| <each question you resolved with the user> | <the answer> |

## Findings

<what you found, with evidence>
```

Use mermaid diagrams where a picture makes a finding
clearer, such as a flow, a dependency graph or a data
model. Do not recommend a course of action.

## Run summary

As you go, keep a list of every tool call you could
not make unassisted: calls that needed the user to
approve a permission prompt, calls that were denied,
and calls that failed and had to be made again in
another form.

End `<%= findings_file %>` with:

```
---

## Run summary

| Field | Value |
| --- | --- |
| Model | <%= model %> |
| Tokens | <best estimate, e.g. ~85k> (estimate) |

### Tool calls that needed help

| Tool call | What happened | Suggested fix |
| --- | --- | --- |
| `<tool call>` | <what happened> | <the permission or instruction that would let it run unassisted> |
```

Leave out the Tool calls that needed help heading and
table when there were none.

## Summary for the user

When the file is written, reply here with a
plain-English summary in exactly this format:

```
Findings written to `<%= findings_file %>`.

**Summary:** <one or two sentences>

**Findings:**
- <file:line where there is one>: <the finding in one line>
```

List every finding, one line each.
~~~~

### `lib/planner/commands/explore.rb` (new)

Modelled on `Commands::Review`. The suffix logic is a private copy of `Review#review_file`;
don't extract a shared helper.

```ruby
# frozen_string_literal: true

module Planner
  module Commands
    # Renders the explore prompt for an iteration file and hands it to the agent.
    class Explore
      TEMPLATE = File.expand_path('../prompts/explore.md.erb', __dir__)
      ITERATION_NAME = /\AITERATION-(\d+)\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        model = parse(args)
        raise UsageError if model.empty? || args.size != 1

        file = args.first
        number = File.basename(file)[ITERATION_NAME, 1]
        raise Error, "#{file} is not an ITERATION-<N>.md file" unless number
        raise Error, "#{file} does not exist" unless File.file?(file)

        findings_file = findings_file(file, number)
        @context.agent.explore(prompt(file, findings_file, model), model:, findings_file:)
      end

      private

      # FINDINGS-<NNN>.md, or the first free FINDINGS-<NNN>-a.md, -b ... -z, -aa ... after it.
      def findings_file(file, number)
        base = File.join(File.dirname(file), format('FINDINGS-%03d', number.to_i))
        path = "#{base}.md"
        suffix = 'a'
        while File.exist?(path)
          path = "#{base}-#{suffix}.md"
          suffix = suffix.succ
        end
        path
      end

      def prompt(file, findings_file, model)
        ERB.new(File.read(TEMPLATE)).result_with_hash(
          iteration_file: file, folder: File.dirname(file), findings_file:, model:,
          title: File.basename(findings_file, '.md')
        )
      end

      # Removes the options from args and returns the chosen model.
      def parse(args)
        model = @context.agent.default_explore_model
        OptionParser.new { |opts| opts.on('-m', '--model MODEL') { |value| model = value } }.parse!(args)
        model
      rescue OptionParser::ParseError
        raise UsageError
      end
    end
  end
end
```

### `lib/planner/agents/claude.rb`

- Interface comment: change it to
  `# Wraps the `claude` CLI. The interface (#plan, #run, #review, #explore, #default_run_model,`
  `# #default_review_model, #default_explore_model) is the contract a future agent must implement.`
  (two comment lines, wrapped to stay within 120 characters).
- After `REVIEW_TOOLS`, add:
  ```ruby
      DEFAULT_EXPLORE_MODEL = 'opus'
      EXPLORE_TOOLS = 'Read,Grep,Glob,Write'
  ```
- After `#review`, add:
  ```ruby
      def explore(prompt, model:, findings_file:)
        @executor.call('claude', '--model', model, "--tools=#{EXPLORE_TOOLS}",
                       "--allowedTools=Edit(#{findings_file})", prompt)
      end
  ```
- After `#default_review_model`, add:
  ```ruby
      def default_explore_model
        DEFAULT_EXPLORE_MODEL
      end
  ```

### `lib/planner/cli.rb`

- In `COMMANDS`, after `'review' => Commands::Review,` add `'explore' => Commands::Explore,`.
- In `USAGE`, after the `planner review …` line add
  `       planner explore [--model <model>] <iteration-file>` (aligned with the other lines).

### `lib/planner.rb`

After `require_relative 'planner/commands/review'` add `require_relative 'planner/commands/explore'`.

### `spec/spec_helper.rb`

In `FakeAgent`, after `#review` add:

```ruby
  def explore(prompt, model:, findings_file:)
    @calls << [:explore, prompt, model, findings_file]
  end
```

and after `#default_review_model` add:

```ruby
  def default_explore_model
    'default-explore-model'
  end
```

### `spec/planner/commands/explore_spec.rb` (new)

```ruby
# frozen_string_literal: true

RSpec.describe Planner::Commands::Explore, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent:, stdin: StringIO.new, stdout: StringIO.new, clock: -> { Time.now })
  end
  let(:iteration) { 'docs/plans/x/ITERATION-001.md' }

  def call = agent.calls.first

  before do
    FileUtils.mkdir_p('docs/plans/x')
    File.write(iteration, "the brief\n")
  end

  it "uses the agent's default model" do
    command.call([iteration])

    expect(agent.calls.size).to eq(1)
    expect(call[0]).to eq(:explore)
    expect(call[2]).to eq('default-explore-model')
  end

  describe 'the model option' do
    it 'accepts -m, --model and --model=' do
      [['-m', 'x'], ['--model', 'x'], ['--model=x']].each do |opts|
        agent.calls.clear
        command.call([*opts, iteration])

        expect(call[2]).to eq('x')
      end
    end

    it 'rejects an empty model' do
      expect { command.call(['-m', '', iteration]) }.to raise_error(Planner::UsageError)
    end
  end

  describe 'the findings file' do
    it 'is FINDINGS-<NNN>.md next to the iteration' do
      command.call([iteration])

      expect(call[3]).to eq('docs/plans/x/FINDINGS-001.md')
    end

    it 'gets -a when the findings exist' do
      File.write('docs/plans/x/FINDINGS-001.md', '')
      command.call([iteration])

      expect(call[3]).to eq('docs/plans/x/FINDINGS-001-a.md')
    end

    it 'gets -b when the findings and -a exist' do
      %w[FINDINGS-001.md FINDINGS-001-a.md].each { |name| File.write("docs/plans/x/#{name}", '') }
      command.call([iteration])

      expect(call[3]).to eq('docs/plans/x/FINDINGS-001-b.md')
    end

    it 'gets -aa when the findings and -a to -z exist' do
      File.write('docs/plans/x/FINDINGS-001.md', '')
      ('a'..'z').each { |letter| File.write("docs/plans/x/FINDINGS-001-#{letter}.md", '') }
      command.call([iteration])

      expect(call[3]).to eq('docs/plans/x/FINDINGS-001-aa.md')
    end

    it 'zero-pads the iteration number' do
      File.write('docs/plans/x/ITERATION-3.md', '')
      command.call(['docs/plans/x/ITERATION-3.md'])

      expect(call[3]).to eq('docs/plans/x/FINDINGS-003.md')
    end
  end

  describe 'the prompt' do
    let(:prompt) do
      command.call([iteration])
      call[1]
    end

    it 'starts with the explore heading and has no ERB leftovers' do
      expect(prompt).to start_with("# Explore From Iteration\n")
      expect(prompt).not_to include('<%')
    end

    it 'names the brief, the findings file, the folder and the title' do
      expect(prompt).to include('Answer the brief `docs/plans/x/ITERATION-001.md`', '`docs/plans/x/FINDINGS-001.md`',
                                '`docs/plans/x/`', '# FINDINGS-001 — <short title>')
    end

    it 'reads FINDINGS files and has the findings sections' do
      expect(prompt).to include('`FINDINGS-*.md`', '## Questions', '## Decisions (resolved, do not revisit)',
                                '## Findings', 'mermaid', 'Do not recommend a course of action.')
    end

    it 'has the run summary with the model' do
      expect(prompt).to include("---\n\n## Run summary", '| Model | default-explore-model |',
                                '### Tool calls that needed help')
      expect(prompt).not_to include('| Status |', '| Started |')
    end

    it 'has the summary format' do
      expect(prompt).to include('## Summary for the user',
                                "Findings written to `docs/plans/x/FINDINGS-001.md`.\n\n**Summary:**",
                                '**Findings:**', 'List every finding, one line each.')
    end

    it 'uses a suffixed findings file in the title' do
      File.write('docs/plans/x/FINDINGS-001.md', '')

      expect(prompt).to include('# FINDINGS-001-a — <short title>')
    end
  end

  describe 'errors' do
    it 'raises a usage error for no file, two files, an unknown flag or a missing -m value' do
      [[], [iteration, iteration], ['--bogus', iteration], [iteration, '-m']].each do |args|
        expect { command.call(args) }.to raise_error(Planner::UsageError)
      end
    end

    it 'rejects a file that is not an ITERATION-<N>.md file' do
      File.write('docs/plans/x/notes.md', '')

      expect { command.call(['docs/plans/x/notes.md']) }
        .to raise_error(Planner::Error, 'docs/plans/x/notes.md is not an ITERATION-<N>.md file')
    end

    it 'rejects a missing iteration file' do
      expect { command.call(['docs/plans/x/ITERATION-009.md']) }
        .to raise_error(Planner::Error, 'docs/plans/x/ITERATION-009.md does not exist')
    end

    it 'checks the name before the existence' do
      expect { command.call(['nope.md']) }
        .to raise_error(Planner::Error, 'nope.md is not an ITERATION-<N>.md file')
    end
  end
end
```

The `let(:prompt)` is lazy, so in the last prompt example `FINDINGS-001.md` is written before the
command runs.

### `spec/planner/agents/claude_spec.rb`

After the "defaults the review model to opus" example, add:

```ruby
  it 'explores with the given model, read-only tools and only the findings file writable' do
    agent.explore('explore it', model: 'opus', findings_file: 'd/FINDINGS-001.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write',
                          '--allowedTools=Edit(d/FINDINGS-001.md)', 'explore it']])
  end

  it 'defaults the explore model to opus' do
    expect(agent.default_explore_model).to eq('opus')
  end
```

### `spec/planner/cli_spec.rb`

After the "prints the message and returns 1 when a command raises Error" example, add:

```ruby
  it 'dispatches explore' do
    expect(cli.call(['explore', 'ITERATION-001.md'])).to eq(1)
    expect(stderr.string).to eq("[planner] ITERATION-001.md does not exist\n")
  end
```

### `spec/exe/planner_spec.rb`

After the "reports a missing iteration file" example, add:

```ruby
  it 'reports a missing iteration file for explore' do
    _out, err, status = planner('explore', 'ITERATION-001.md')

    expect(status.exitstatus).to eq(1)
    expect(err).to eq("[planner] ITERATION-001.md does not exist\n")
  end
```

This runs the real executable, so it covers the require in `lib/planner.rb` and the `COMMANDS`
entry together. The real `Agents::Claude#default_explore_model` is called before the file check,
and nothing is executed because the file does not exist.

### `README.md`

Follow `.claude/skills/update-readme/SKILL.md`. In Usage, after the `planner review` bullet, add
this bullet as one line:

```
- `planner explore [--model <model>] <iteration-file>`: have the agent answer an `ITERATION-<N>.md` brief by exploring the code or data, asking you about anything unclear, and write a read-only `FINDINGS-<N>.md` next to it, then summarise it in the session (default model `opus`).
```

### `docs/GLOSSARY.md`

After the **review file** entry, add as one line:

```
- **findings file**: `FINDINGS-<NNN>.md`, or `FINDINGS-<NNN>-<letter>.md` for a later exploration of the same iteration. Answers to the questions in an iteration file, found by exploring the code or data. Written by `planner explore`, and never executed.
```

## Verification

1. `bundle exec rake` passes: all specs, including the new ones, plus RuboCop with no offences.
2. Render the prompt by hand from the repo root, with a fake agent that prints its arguments.
   The `--` stops Ruby from reading the arguments after the script as its own options:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def explore(x, model:, findings_file:) = puts(x, model, findings_file); def default_explore_model = "opus" }.new; Planner::Commands::Explore.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- docs/plans/202610291422-add-explore-task-to-planner/ITERATION-001.md`
   The output starts with `# Explore From Iteration` and names
   `docs/plans/202610291422-add-explore-task-to-planner/FINDINGS-001.md` throughout. The
   findings structure's title line reads `# FINDINGS-001 — <short title>`, the run summary has
   `| Model | opus |`, and there are no ERB leftovers. The last two lines are `opus` and the
   findings file path.
3. Run it again with the model option:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def explore(x, model:, findings_file:) = puts(x, model, findings_file); def default_explore_model = "opus" }.new; Planner::Commands::Explore.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- -m sonnet docs/plans/202610291422-add-explore-task-to-planner/ITERATION-001.md`
   The run summary has `| Model | sonnet |` and the second-to-last line is `sonnet`.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/commands/explore.rb lib/planner/prompts/explore.md.erb lib/planner/agents/claude.rb lib/planner/cli.rb lib/planner.rb spec/planner/commands/explore_spec.rb spec/planner/agents/claude_spec.rb spec/planner/cli_spec.rb spec/exe/planner_spec.rb spec/spec_helper.rb README.md docs/GLOSSARY.md docs/plans/202610291422-add-explore-task-to-planner/ITERATION-001.md docs/plans/202610291422-add-explore-task-to-planner/PLAN-001.md docs/plans/202610291422-add-explore-task-to-planner/REVIEW-001.md
```

Write the message to a file and commit with `git commit -F <file>`. The message follows the
`commit-message` skill's rules: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Add a planner explore command

planner explore takes an iteration brief and has the agent answer it
by exploring the code or data, without changing anything. The agent
asks about anything unclear before writing, then writes a read-only
FINDINGS file next to the brief that ends with a run summary, and
replies with a short summary in the session.

The README and glossary now cover the command and the findings file.

Assisted-by: <agent> (<model>)
```
