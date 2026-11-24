# frozen_string_literal: true

RSpec.describe Planner::Commands::Next, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:stdout) { StringIO.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent: FakeAgent.new, stdin: StringIO.new, stdout:, clock: -> { Time.now })
  end
  let(:folder) { 'docs/plans/x' }

  def touch(*names) = names.each { |name| File.write(File.join(folder, name), '') }

  before { FileUtils.mkdir_p(folder) }

  it 'creates an empty ITERATION-001.md in a folder with no files' do
    command.call([folder])

    expect(File.size("#{folder}/ITERATION-001.md")).to eq(0)
    expect(stdout.string).to eq("docs/plans/x/ITERATION-001.md\n")
  end

  it 'creates the next number after the existing iteration files' do
    touch('ITERATION-001.md', 'ITERATION-002.md')

    command.call([folder])

    expect(File.size("#{folder}/ITERATION-003.md")).to eq(0)
    expect(stdout.string).to eq("docs/plans/x/ITERATION-003.md\n")
  end

  it 'uses the highest number, not the count' do
    touch('ITERATION-001.md', 'ITERATION-005.md')

    command.call([folder])

    expect(File.file?("#{folder}/ITERATION-006.md")).to be(true)
  end

  it 'ignores other kinds of file' do
    touch('ITERATION-001.md', 'PLAN-001.md', 'FINDINGS-004.md', 'REVIEW-003.md')

    command.call([folder])

    expect(File.file?("#{folder}/ITERATION-002.md")).to be(true)
  end

  it 'ignores unpadded and lettered names' do
    touch('ITERATION-001.md', 'ITERATION-15.md', 'ITERATION-002-a.md')

    command.call([folder])

    expect(File.file?("#{folder}/ITERATION-002.md")).to be(true)
  end

  it 'creates the file even when the latest iteration is empty' do
    touch('ITERATION-001.md')

    command.call([folder])

    expect(File.file?("#{folder}/ITERATION-002.md")).to be(true)
  end

  it 'drops a trailing slash' do
    command.call(['docs/plans/x/'])

    expect(stdout.string).to eq("docs/plans/x/ITERATION-001.md\n")
  end

  it 'leaves existing files unchanged' do
    File.write("#{folder}/ITERATION-001.md", 'brief')

    command.call([folder])

    expect(File.read("#{folder}/ITERATION-001.md")).to eq('brief')
  end

  it 'raises for a missing path' do
    expect { command.call(['nope']) }.to raise_error(Planner::Error, 'nope is not a directory')
  end

  it 'raises when given a file' do
    touch('ITERATION-001.md')
    file = "#{folder}/ITERATION-001.md"

    expect { command.call([file]) }.to raise_error(Planner::Error, "#{file} is not a directory")
  end

  it 'raises a usage error with no arguments, two arguments or an option' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
    expect { command.call([folder, folder]) }.to raise_error(Planner::UsageError)
    expect { command.call(['--dir', folder]) }.to raise_error(Planner::UsageError)
  end
end
