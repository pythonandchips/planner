# frozen_string_literal: true

RSpec.describe Planner::Agents::Claude do
  subject(:agent) { described_class.new(executor: ->(*argv) { calls << argv }) }

  let(:calls) { [] }

  it 'plans with opus using the given prompt' do
    agent.plan('do the plan')

    expect(calls).to eq([['claude', '--model', 'opus', 'do the plan']])
  end

  it 'runs the prompt with the given model' do
    agent.run('do it', model: 'haiku')

    expect(calls).to eq([['claude', '--model', 'haiku', 'do it']])
  end

  it 'defaults the run model to sonnet' do
    expect(agent.default_run_model).to eq('sonnet')
  end
end
