# frozen_string_literal: true

RSpec.describe Planner::CLI, :aggregate_failures do
  subject(:cli) { described_class.new(context:, stderr:) }

  let(:stderr) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, agent: FakeAgent.new, stdout:, clock: lambda {
      Time.utc(2026, 10, 27, 12, 16)
    })
  end

  it 'prints usage and returns 1 with no args' do
    expect(cli.call([])).to eq(1)
    expect(stderr.string).to eq(described_class::USAGE)
  end

  it 'prints usage and returns 1 for an unknown command' do
    expect(cli.call(['bogus'])).to eq(1)
    expect(stderr.string).to eq(described_class::USAGE)
  end

  it 'prints usage and returns 1 when a command raises UsageError' do
    expect(cli.call(['new'])).to eq(1)
    expect(stderr.string).to eq(described_class::USAGE)
  end

  it 'prints the message and returns 1 when a command raises Error' do
    expect(cli.call(['plan', 'missing.md'])).to eq(1)
    expect(stderr.string).to eq("[planner] missing.md does not exist\n")
  end

  it 'returns 0 on success' do
    expect(cli.call(%w[new Hello])).to eq(0)
    expect(stdout.string).to eq("docs/plans/202610271216-hello\n")
  end
end
