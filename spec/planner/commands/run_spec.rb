# frozen_string_literal: true

RSpec.describe Planner::Commands::Run do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) { Planner::Context.new(root: Pathname.pwd, agent:, stdout: StringIO.new, clock: -> { Time.now }) }

  before { File.write('PLAN-001.md', "line one\n\nline two\n\n\n") }

  it "uses the agent's default model" do
    command.call(['PLAN-001.md'])

    expect(agent.calls).to eq([[:run, "line one\n\nline two", 'default-model']])
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
