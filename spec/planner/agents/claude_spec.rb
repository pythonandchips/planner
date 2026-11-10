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

  it 'lists the tools a run needs' do
    expect(agent.run_tools).to eq(%w[Bash Read Edit Write Glob Grep Skill])
  end

  it 'reviews with the given model, read-only tools and only the report and plan writable' do
    agent.review('review it', model: 'opus', report_file: 'd/REVIEW-001.md', plan_file: 'd/PLAN-001.md',
                              toc_file: 'd/TABLE-OF-CONTENT.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write',
                          '--allowedTools=Edit(d/REVIEW-001.md),Edit(d/PLAN-001.md),Edit(d/TABLE-OF-CONTENT.md)',
                          'review it']])
  end

  it 'defaults the review model to opus' do
    expect(agent.default_review_model).to eq('opus')
  end

  it 'explores with the given model, read-only tools plus WebFetch, and the findings file writable' do
    agent.explore('explore it', model: 'opus', findings_file: 'd/FINDINGS-001.md',
                                toc_file: 'd/TABLE-OF-CONTENT.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write,WebFetch',
                          '--allowedTools=Edit(d/FINDINGS-001.md),Edit(d/TABLE-OF-CONTENT.md),WebFetch',
                          'explore it']])
  end

  it 'defaults the explore model to opus' do
    expect(agent.default_explore_model).to eq('opus')
  end

  it 'summarises with the given model, shell and web tools, and only the summary paths and toc writable' do
    agent.summarise('sum it', model: 'opus', summary_base: 'd/SUMMARY-001', toc_file: 'd/TABLE-OF-CONTENT.md')

    expect(calls).to eq([['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write,Bash,WebFetch,Skill',
                          '--allowedTools=Edit(d/SUMMARY-001.*),Edit(d/SUMMARY-001/**),Edit(d/TABLE-OF-CONTENT.md)',
                          'sum it']])
  end

  it 'defaults the summarise model to opus' do
    expect(agent.default_summarise_model).to eq('opus')
  end

  it 'writes the table of contents headless with the given model and only that file writable' do
    agent.toc('list it', model: 'haiku', toc_file: 'd/TABLE-OF-CONTENT.md')

    expect(calls).to eq([['claude', '-p', '--model', 'haiku', '--tools=Read,Grep,Glob,Write',
                          '--allowedTools=Edit(d/TABLE-OF-CONTENT.md)', 'list it']])
  end

  it 'defaults the toc model to haiku' do
    expect(agent.default_toc_model).to eq('haiku')
  end
end
