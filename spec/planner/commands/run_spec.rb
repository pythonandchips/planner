# frozen_string_literal: true

RSpec.describe Planner::Commands::Run, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) { Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills', agent:, stdin: StringIO.new, stdout: StringIO.new, clock: -> { Time.now }) }

  before { File.write('PLAN-001.md', "line one\n\nline two\n\n\n") }

  it "uses the agent's default model" do
    command.call(['PLAN-001.md'])

    expect(agent.calls.size).to eq(1)
    expect(agent.calls.first.first).to eq(:run)
    expect(agent.calls.first.last).to eq('default-model')
  end

  describe 'the prompt' do
    let(:prompt) do
      command.call(['PLAN-001.md'])
      agent.calls.first[1]
    end

    it 'starts with the run heading' do
      expect(prompt).to start_with("# Run Plan\n")
    end

    it 'names the plan file and says to follow it exactly' do
      expect(prompt).to include('Implement the plan `PLAN-001.md`', 'Follow it exactly.')
    end

    it 'takes the literal reading and does not commit when stopping' do
      expect(prompt).to include("take the\n   most literal reading", 'Do not commit.')
    end

    it 'asks for a plain English report of what is left' do
      expect(prompt).to include('what is still left to do')
    end

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

    it 'ends with the plan, keeping inner newlines and stripping trailing ones' do
      expect(prompt).to end_with("## Plan\n\nline one\n\nline two\n")
    end

    it 'asks for the start time before anything else' do
      expect(prompt).to include('Before anything else, run `date -u +%Y-%m-%dT%H:%M:%SZ`')
    end

    it 'writes the deviations and stats on finish and on stop, staging the plan file and fixed files' do
      expect(prompt).to include(
        '7. Write the deviations, then the stats, when you',
        'stage `PLAN-001.md` and every file'
      )
    end

    it 'appends the stats to the plan file' do
      expect(prompt).to include('end of `PLAN-001.md`, below everything already',
                                "---\n\n## Stats\n\n| Field | Value |")
    end

    it 'fills in the model and asks for a labelled token estimate' do
      expect(prompt).to include('| Model | default-model |', '(estimate) |')
    end

    it 'lists commands that needed help' do
      expect(prompt).to include("### Commands that needed help\n\n| Command | What happened | Suggested fix |")
    end

    it 'leaves no ERB tags behind' do
      expect(prompt).not_to include('<%')
    end
  end

  [%w[-m x], %w[--model x], %w[--model=x], %w[-mx]].each do |flags|
    it "accepts #{flags.join(' ')}" do
      command.call([*flags, 'PLAN-001.md'])

      expect(agent.calls.first.last).to eq('x')
    end
  end

  it 'accepts the model after the file' do
    command.call(['PLAN-001.md', '-m', 'x'])

    expect(agent.calls.first.last).to eq('x')
  end

  it 'puts the chosen model in the stats' do
    command.call(['-m', 'x', 'PLAN-001.md'])

    expect(agent.calls.first[1]).to include('| Model | x |')
  end

  it 'raises UsageError for a missing -m value' do
    expect { command.call(['PLAN-001.md', '-m']) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for an empty model' do
    expect { command.call(['-m', '', 'PLAN-001.md']) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for two files' do
    expect { command.call(%w[PLAN-001.md PLAN-002.md]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for no file' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for an unknown flag' do
    expect { command.call(%w[--bogus PLAN-001.md]) }.to raise_error(Planner::UsageError)
  end

  it 'raises Error for a missing file' do
    expect { command.call(['nope.md']) }.to raise_error(Planner::Error, 'nope.md does not exist')
  end

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

  it 'updates the table of contents when it exists' do
    command.call(['PLAN-001.md'])

    expect(agent.calls.first[1]).to include('the stats and the table of',
                                            '`./TABLE-OF-CONTENT.md` if you updated it',
                                            'If `./TABLE-OF-CONTENT.md` exists')
  end
end
