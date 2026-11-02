# frozen_string_literal: true

RSpec.describe Planner::Commands::Toc, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent:, stdin: StringIO.new, stdout: StringIO.new, clock: -> { Time.now })
  end
  let(:folder) { 'docs/plans/x' }

  def call = agent.calls.first

  before { FileUtils.mkdir_p(folder) }

  it "uses the agent's default model" do
    command.call([folder])

    expect(agent.calls.size).to eq(1)
    expect(call[0]).to eq(:toc)
    expect(call[2]).to eq('default-toc-model')
  end

  describe 'the model option' do
    it 'accepts -m, --model and --model=' do
      [['-m', 'x'], ['--model', 'x'], ['--model=x']].each do |opts|
        agent.calls.clear
        command.call([*opts, folder])

        expect(call[2]).to eq('x')
      end
    end

    it 'rejects an empty model' do
      expect { command.call(['-m', '', folder]) }.to raise_error(Planner::UsageError)
    end
  end

  it 'passes the table of contents file to the agent' do
    command.call([folder])
    expect(call[3]).to eq('docs/plans/x/TABLE-OF-CONTENT.md')

    agent.calls.clear
    command.call(["#{folder}/"])
    expect(call[3]).to eq('docs/plans/x/TABLE-OF-CONTENT.md')
  end

  describe 'the prompt' do
    let(:prompt) do
      command.call([folder])
      call[1]
    end

    it 'renders the toc prompt' do
      expect(prompt).to start_with("# Table of Contents\n")
      expect(prompt).not_to include('<%', 'do not create it')
      expect(prompt).to include('You may write only `docs/plans/x/TABLE-OF-CONTENT.md`.', 'replace it entirely',
                                '# Table of contents — x',
                                'Table of contents written to `docs/plans/x/TABLE-OF-CONTENT.md`.')
    end
  end

  it 'raises UsageError for no args, two args, an unknown flag and a missing -m value' do
    [[], [folder, folder], ['--bogus', folder], ['-m']].each do |args|
      expect { command.call(args) }.to raise_error(Planner::UsageError)
    end
  end

  it 'raises Error for a missing folder or a file' do
    File.write('notes.md', 'x')

    expect { command.call(['docs/plans/nope']) }
      .to raise_error(Planner::Error, 'docs/plans/nope is not a directory')
    expect { command.call(['notes.md']) }.to raise_error(Planner::Error, 'notes.md is not a directory')
  end
end
