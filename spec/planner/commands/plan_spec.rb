# frozen_string_literal: true

RSpec.describe Planner::Commands::Plan do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) { Planner::Context.new(root: Pathname.pwd, agent:, stdout: StringIO.new, clock: -> { Time.now }) }

  it 'hands the file to the agent exactly as given' do
    FileUtils.mkdir_p('docs')
    File.write('docs/ITERATION-001.md', 'x')

    command.call(['docs/ITERATION-001.md'])

    expect(agent.calls).to eq([[:plan, 'docs/ITERATION-001.md']])
  end

  it 'raises UsageError without a file' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
  end

  it 'raises Error for a missing file' do
    expect { command.call(['nope.md']) }.to raise_error(Planner::Error, 'nope.md does not exist')
  end
end
