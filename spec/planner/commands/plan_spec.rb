# frozen_string_literal: true

RSpec.describe Planner::Commands::Plan, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) { Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills', agent:, stdin: StringIO.new, stdout: StringIO.new, clock: -> { Time.now }) }

  def write_iteration(name)
    FileUtils.mkdir_p('docs/plans/x')
    File.write("docs/plans/x/#{name}", 'x')
  end

  it 'hands the rendered prompt to the agent' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    expect(agent.calls).to match([[:plan, a_string_starting_with("# Plan From Iteration\n")]])
    expect(agent.calls.first.last).to include('docs/plans/x/ITERATION-001.md', 'docs/plans/x/PLAN-001.md')
    expect(agent.calls.first.last).not_to include('<%')
  end

  it 'zero-pads the plan number' do
    write_iteration('ITERATION-3.md')

    command.call(['docs/plans/x/ITERATION-3.md'])

    expect(agent.calls.first.last).to include('docs/plans/x/PLAN-003.md')
  end

  it 'raises UsageError without a file' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
  end

  it 'raises Error for a missing file' do
    expect { command.call(['docs/plans/x/ITERATION-009.md']) }
      .to raise_error(Planner::Error, 'docs/plans/x/ITERATION-009.md does not exist')
  end

  it 'raises Error for a file not named ITERATION-<N>.md' do
    File.write('notes.md', 'x')

    expect { command.call(['notes.md']) }
      .to raise_error(Planner::Error, 'notes.md is not an ITERATION-<N>.md file')
  end

  it 'checks the name before existence' do
    expect { command.call(['nope.md']) }
      .to raise_error(Planner::Error, 'nope.md is not an ITERATION-<N>.md file')
  end

  it 'updates the table of contents when it exists' do
    write_iteration('ITERATION-001.md')
    command.call(['docs/plans/x/ITERATION-001.md'])

    expect(agent.calls.first.last).to include('5. **Update the table of contents.**',
                                              'If `docs/plans/x/TABLE_OF_CONTENT.md` exists, list',
                                              '## Table of contents')
  end
end
