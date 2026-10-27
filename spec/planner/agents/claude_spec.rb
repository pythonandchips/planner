# frozen_string_literal: true

RSpec.describe Planner::Agents::Claude do
  subject(:agent) { described_class.new(executor: ->(*argv) { calls << argv }) }

  let(:calls) { [] }

  it 'plans with opus via the plan-from-iteration skill' do
    agent.plan('docs/ITERATION-001.md')

    expect(calls).to eq([['claude', '--model', 'opus', '/plan-from-iteration docs/ITERATION-001.md']])
  end

  it 'runs the prompt with the given model' do
    agent.run('do it', model: 'haiku')

    expect(calls).to eq([['claude', '--model', 'haiku', 'do it']])
  end

  it 'defaults the run model to sonnet' do
    expect(agent.default_run_model).to eq('sonnet')
  end
end
