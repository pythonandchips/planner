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

  describe 'deep exploring' do
    let(:argv) do
      agent.explore_deep('dig in', model: 'opus', findings_file: 'd/FINDINGS-001.md',
                                   toc_file: 'd/TABLE-OF-CONTENT.md', branch_prefix: 'x')
      calls.first
    end

    it 'runs claude with web search, a shell and subagents, and only the findings and toc editable' do
      expect(argv[0..4]).to eq(
        ['claude', '--model', 'opus', '--tools=Read,Grep,Glob,Write,Edit,WebFetch,WebSearch,Bash,Agent,Skill',
         '--allowedTools=Edit(d/FINDINGS-001.md),Edit(d/TABLE-OF-CONTENT.md),WebFetch,WebSearch']
      )
    end

    it 'removes every MCP tool' do
      expect(argv[5]).to eq('--disallowedTools=mcp__*')
    end

    it 'turns off claude.ai connectors, bases worktrees on HEAD, asks before installs and sandboxes the shell' do # rubocop:disable RSpec/ExampleLength
      expect(JSON.parse(argv[6].delete_prefix('--settings='))).to eq(
        'disableClaudeAiConnectors' => true, 'worktree' => { 'baseRef' => 'head' },
        'permissions' => { 'ask' => ['Bash(bundle install *)', 'Bash(bundle add *)', 'Bash(gem install *)',
                                     'Bash(npm install *)', 'Bash(yarn add *)', 'Bash(pip install *)'] },
        'sandbox' => { 'enabled' => true, 'autoAllowBashIfSandboxed' => true, 'allowUnsandboxedCommands' => true,
                       'network' => { 'allowedDomains' => [] } }
      )
    end

    it 'defines the spike subagent in its own worktree' do # rubocop:disable RSpec/ExampleLength
      expect(JSON.parse(argv[7].delete_prefix('--agents='))).to eq(
        'spike' => { 'description' =>
                       'Answers one question or builds one approach to the brief in its own worktree, then reports.',
                     'prompt' => described_class::SPIKE_PROMPT,
                     'tools' => %w[Read Grep Glob Edit Write Bash WebFetch WebSearch],
                     'model' => 'inherit', 'maxTurns' => 200, 'isolation' => 'worktree' }
      )
    end

    it 'tells the spike to commit only an approach, on its own branch' do
      expect(described_class::SPIKE_PROMPT).to include('Never commit it, and do not switch branch.',
                                                       'git switch -c <branch>', "git log -1 --format='%h %s'",
                                                       'Never remove a worktree or a branch, and never push.')
    end

    it 'passes the prompt last' do
      expect(argv[8..]).to eq(['dig in'])
    end
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
