# frozen_string_literal: true

RSpec.describe Planner::Commands::New, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:stdout) { StringIO.new }
  let(:root) { Pathname.pwd }
  let(:context) do
    Planner::Context.new(root:, agent: FakeAgent.new, stdout:, clock: -> { Time.new(2026, 10, 27, 12, 16) })
  end

  it 'creates the plan folder and prints its relative path' do
    command.call(['Hello World'])

    expect(root.join('docs/plans/202610271216-hello-world')).to be_directory
    expect(stdout.string).to eq("docs/plans/202610271216-hello-world\n")
  end

  it 'ignores extra args' do
    command.call(%w[Hello extra])

    expect(stdout.string).to eq("docs/plans/202610271216-hello\n")
  end

  it 'raises UsageError without a name' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for an empty name' do
    expect { command.call(['']) }.to raise_error(Planner::UsageError)
  end

  it 'raises Error when the name has no usable characters' do
    expect { command.call(['!!!']) }
      .to raise_error(Planner::Error, "'!!!' does not contain any usable characters")
  end

  it 'raises Error when the folder already exists' do
    command.call(['Hello'])

    expect { command.call(['Hello']) }
      .to raise_error(Planner::Error, "#{root}/docs/plans/202610271216-hello already exists")
  end
end
