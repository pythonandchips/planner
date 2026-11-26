# frozen_string_literal: true

RSpec.describe Planner::Commands::Feedback, :aggregate_failures do
  subject(:command) { described_class.new(context, gh: fake_gh) }

  let(:stdout) { StringIO.new }
  let(:agent) { FakeAgent.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent:, stdin: StringIO.new, stdout:, clock: -> { Time.now })
  end
  let(:folder) { 'docs/plans/x' }
  let(:view) { { 'number' => 42, 'title' => 'Add login', 'url' => 'https://github.com/o/r/pull/42' } }
  let(:conversation) { [{ 'author' => { 'login' => 'alice' }, 'body' => 'Please fix.' }] }
  let(:fake_gh) { FakeGh.new(view:, graphql: graphql) }

  def page(nodes) = { 'pageInfo' => { 'hasNextPage' => false }, 'nodes' => nodes }

  def graphql
    pull = { 'reviewThreads' => page([]), 'reviews' => page([]), 'comments' => page(conversation) }
    { 'data' => { 'repository' => { 'pullRequest' => pull } } }
  end

  before { FileUtils.mkdir_p(folder) }

  it 'writes the next iteration file, prints its path and plans it' do
    File.write("#{folder}/ITERATION-001.md", 'brief')

    command.call([folder, '42'])

    expect(File.read("#{folder}/ITERATION-002.md")).to include('# Review feedback — PR #42: Add login', 'Please fix.')
    expect(stdout.string).to eq("docs/plans/x/ITERATION-002.md\n")
    expect(agent.calls.first.last).to include('docs/plans/x/ITERATION-002.md', 'docs/plans/x/PLAN-002.md')
  end

  it 'writes ITERATION-001.md in an empty folder' do
    command.call([folder, '42'])

    expect(File.file?("#{folder}/ITERATION-001.md")).to be(true)
  end

  it 'drops a trailing slash on the folder' do
    command.call(['docs/plans/x/', '42'])

    expect(stdout.string).to eq("docs/plans/x/ITERATION-001.md\n")
  end

  context 'when no comments are left' do
    let(:conversation) { [] }

    it 'raises, writes no file and calls no agent' do
      expect { command.call([folder, '42']) }.to raise_error(Planner::Error, '42 has no review comments')
      expect(Dir.children(folder)).to be_empty
      expect(agent.calls).to be_empty
    end
  end

  it 'raises for a folder that is not a directory, without calling gh' do
    expect { command.call(%w[nope 42]) }.to raise_error(Planner::Error, 'nope is not a directory')
    expect(fake_gh.calls).to be_empty
  end

  it 'raises a usage error with no, one or three arguments, or an option' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
    expect { command.call([folder]) }.to raise_error(Planner::UsageError)
    expect { command.call([folder, '42', 'x']) }.to raise_error(Planner::UsageError)
    expect { command.call(['--model', 'x', '42']) }.to raise_error(Planner::UsageError)
  end
end
