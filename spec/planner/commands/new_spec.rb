# frozen_string_literal: true

RSpec.describe Planner::Commands::New, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:stdout) { StringIO.new }
  let(:root) { Pathname.pwd }
  let(:context) do
    Planner::Context.new(root:, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent: FakeAgent.new, stdin: StringIO.new, stdout:,
                         clock: -> { Time.new(2026, 10, 27, 12, 16) })
  end

  it 'creates the plan folder and prints its relative path' do
    command.call(['Hello World'])

    expect(root.join('docs/plans/202610271216-hello-world')).to be_directory
    expect(stdout.string).to eq("docs/plans/202610271216-hello-world\n")
  end

  it 'ignores extra args' do
    command.call(%w[Hello extra])

    expect(stdout.string).to eq("docs/plans/202610271216-hello\n")
  end

  it 'creates the folder under --dir and prints its path' do
    command.call(['--dir', 'work/plans', 'Hello'])

    expect(root.join('work/plans/202610271216-hello')).to be_directory
    expect(stdout.string).to eq("work/plans/202610271216-hello\n")
  end

  it 'accepts -d' do
    command.call(%w[-d work Hello])

    expect(stdout.string).to eq("work/202610271216-hello\n")
  end

  it 'accepts the option after the name' do
    command.call(%w[Hello --dir work])

    expect(stdout.string).to eq("work/202610271216-hello\n")
  end

  context 'with a project folder' do
    let(:root) { Pathname.pwd / 'project' }

    before { root.mkpath }

    it 'creates the folder in an absolute --dir and prints the absolute path' do
      elsewhere = (Pathname.pwd / 'elsewhere').to_s

      command.call(['--dir', elsewhere, 'Hello'])

      expect(Pathname.pwd.join('elsewhere/202610271216-hello')).to be_directory
      expect(stdout.string).to eq("#{elsewhere}/202610271216-hello\n")
    end

    it 'creates the folder in a relative --dir outside the root' do
      command.call(['--dir', '../outside', 'Hello'])

      expect(Pathname.pwd.join('outside/202610271216-hello')).to be_directory
      expect(stdout.string).to eq("../outside/202610271216-hello\n")
    end
  end

  it 'raises UsageError for an empty --dir' do
    expect { command.call(['--dir', '', 'Hello']) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for --dir without a value' do
    expect { command.call(%w[Hello --dir]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for an unknown option' do
    expect { command.call(%w[--nope Hello]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError without a name' do
    expect { command.call([]) }.to raise_error(Planner::UsageError)
  end

  it 'raises UsageError for an empty name' do
    expect { command.call(['']) }.to raise_error(Planner::UsageError)
  end

  it 'raises Error when the name has no usable characters' do
    expect { command.call(['!!!']) }
      .to raise_error(Planner::Error, "'!!!' does not contain any usable characters")
  end

  it 'raises Error when the folder already exists' do
    command.call(['Hello'])

    expect { command.call(['Hello']) }
      .to raise_error(Planner::Error, "#{root}/docs/plans/202610271216-hello already exists")
  end

  it 'names the --dir folder when it already exists' do
    command.call(['--dir', 'work', 'Hello'])

    expect { command.call(['--dir', 'work', 'Hello']) }
      .to raise_error(Planner::Error, "#{root}/work/202610271216-hello already exists")
  end
end
