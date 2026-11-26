# frozen_string_literal: true

RSpec.describe Planner::Tools::Gh, :aggregate_failures do
  subject(:gh) { described_class.new(runner:) }

  let(:status) { instance_double(Process::Status, success?: true) }
  let(:calls) { [] }
  let(:runner) do
    lambda do |*args|
      calls << args
      ['{"a":1}', '', status]
    end
  end

  it 'parses the JSON gh prints and passes the arguments after gh' do
    expect(gh.json('pr', 'view', '42')).to eq('a' => 1)
    expect(calls).to eq([%w[gh pr view 42]])
  end

  context 'when gh exits non-zero' do
    let(:status) { instance_double(Process::Status, success?: false) }
    let(:runner) { ->(*) { ['', "not logged in\n", status] } }

    it 'raises with the stderr' do
      expect { gh.json('pr') }.to raise_error(Planner::Error, 'gh failed: not logged in')
    end
  end

  context 'when gh is not installed' do
    let(:runner) { ->(*) { raise Errno::ENOENT } }

    it 'raises a helpful error' do
      expect { gh.json('pr') }.to raise_error(Planner::Error, 'gh is not installed; see https://cli.github.com')
    end
  end
end
