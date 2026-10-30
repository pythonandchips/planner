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

    it 'ends with the plan, keeping inner newlines and stripping trailing ones' do
      expect(prompt).to end_with("## Plan\n\nline one\n\nline two\n")
    end

    it 'asks for the start time before anything else' do
      expect(prompt).to include('Before anything else, run `date -u +%Y-%m-%dT%H:%M:%SZ`')
    end

    it 'writes the stats on finish and on stop, staging the plan file' do
      expect(prompt).to include(
        '6. Write the stats when you finish and when you',
        'stage `PLAN-001.md` with the commit'
      )
    end

    it 'prepends the stats to the plan file' do
      expect(prompt).to include('top of `PLAN-001.md`, above everything already', "## Stats\n\n| Field | Value |")
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
end
