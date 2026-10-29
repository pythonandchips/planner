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

  it 'reviews with the given model, read-only tools and only the report writable' do
    agent.review('review it', model: 'opus', report_file: 'd/REVIEW-001.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write',
                          '--allowedTools=Edit(d/REVIEW-001.md)', 'review it']])
  end

  it 'defaults the review model to opus' do
    expect(agent.default_review_model).to eq('opus')
  end

  it 'explores with the given model, read-only tools and only the findings file writable' do
    agent.explore('explore it', model: 'opus', findings_file: 'd/FINDINGS-001.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write',
                          '--allowedTools=Edit(d/FINDINGS-001.md)', 'explore it']])
  end

  it 'defaults the explore model to opus' do
    expect(agent.default_explore_model).to eq('opus')
  end
end
