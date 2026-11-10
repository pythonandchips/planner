# frozen_string_literal: true

RSpec.describe Planner::Commands::Summarise, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:stdin) { StringIO.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent:, stdin:, stdout: StringIO.new, clock: -> { Time.now })
  end
  let(:plan) { 'docs/plans/x/PLAN-002.md' }

  def call = agent.calls.first

  before do
    FileUtils.mkdir_p('docs/plans/x')
    File.write(plan, "the plan\n")
  end

  it "uses the agent's default model" do
    command.call([plan])

    expect(agent.calls.size).to eq(1)
    expect(call[0]).to eq(:summarise)
    expect(call[2]).to eq('default-summarise-model')
  end

  it 'passes the table of contents path to the agent' do
    command.call([plan])

    expect(call[4]).to eq('docs/plans/x/TABLE-OF-CONTENT.md')
  end

  describe 'the model option' do
    it 'accepts -m, --model and --model=' do
      [['-m', 'x'], ['--model', 'x'], ['--model=x']].each do |opts|
        agent.calls.clear
        command.call([*opts, plan])

        expect(call[2]).to eq('x')
      end
    end

    it 'rejects an empty model' do
      expect { command.call(['-m', '', plan]) }.to raise_error(Planner::UsageError)
    end
  end

  describe 'the source file' do
    it 'accepts review and findings files, lettered or not' do # rubocop:disable RSpec/ExampleLength
      %w[REVIEW-002.md REVIEW-002-a.md FINDINGS-002.md FINDINGS-002-aa.md].each do |name|
        File.write("docs/plans/x/#{name}", '')
        agent.calls.clear
        command.call(["docs/plans/x/#{name}"])

        expect(call[3]).to eq('docs/plans/x/SUMMARY-002')
      end
    end
  end

  describe 'the summary base' do
    it 'is SUMMARY-<NNN> next to the source file' do
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-002')
    end

    it 'gets -a when a summary file with any extension exists' do
      File.write('docs/plans/x/SUMMARY-002.gif', '')
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-002-a')
    end

    it 'gets -a when a summary folder exists' do
      FileUtils.mkdir_p('docs/plans/x/SUMMARY-002')
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-002-a')
    end

    it 'gets -b when the summary and -a exist' do
      %w[SUMMARY-002.md SUMMARY-002-a.mp3].each { |name| File.write("docs/plans/x/#{name}", '') }
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-002-b')
    end

    it 'gets -aa when the summary and -a to -z exist' do
      File.write('docs/plans/x/SUMMARY-002.md', '')
      ('a'..'z').each { |letter| File.write("docs/plans/x/SUMMARY-002-#{letter}.md", '') }
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-002-aa')
    end

    it 'zero-pads the source number' do
      File.write('docs/plans/x/PLAN-3.md', '')
      command.call(['docs/plans/x/PLAN-3.md'])

      expect(call[3]).to eq('docs/plans/x/SUMMARY-003')
    end
  end

  describe 'the prompt with no brief' do
    let(:prompt) do
      command.call([plan])
      call[1]
    end

    it 'starts with the summarise heading and has no ERB leftovers' do
      expect(prompt).to start_with("# Summarise\n")
      expect(prompt).not_to include('<%')
    end

    it 'names the source file, the folder and the summary paths' do
      expect(prompt).to include('Summarise `docs/plans/x/PLAN-002.md`', '`docs/plans/x/`',
                                '`docs/plans/x/SUMMARY-002.<ext>`', '`docs/plans/x/SUMMARY-002/`')
    end

    it 'asks for a markdown summary in the session' do
      expect(prompt).to include('No brief was given.', 'Write nothing to disk.')
    end

    it 'has the rules on sources, tools, temporary files and one output' do
      expect(prompt).to include('full reference', 'Never install software.', 'mktemp -d',
                                'Write the output at most once.')
    end

    it 'commits only when the brief asks' do
      expect(prompt).to include('## Committing', 'Commit only when the brief asks for a commit.',
                                '`commit-message` skill')
    end

    it 'has both reply formats with the model in the stats' do
      expect(prompt).to include('## Summary for the user', "Summary written to `<path>`.\n\n",
                                "<the summary>\n\n**Stats:**", '| Model | default-summarise-model |',
                                '**Commands that needed help:**', 'Never add stats to the output.')
    end

    it 'updates the table of contents when it exists' do
      expect(prompt).to include('If `docs/plans/x/TABLE-OF-CONTENT.md` exists',
                                '# Table of contents — x')
    end

    it 'uses a suffixed summary base' do
      File.write('docs/plans/x/SUMMARY-002.md', '')

      expect(prompt).to include('`docs/plans/x/SUMMARY-002-a.<ext>`')
    end
  end

  describe 'the prompt with a brief' do
    def prompt_for(*args)
      agent.calls.clear
      command.call(args)
      call[1]
    end

    it 'puts the brief in the prompt' do
      prompt = prompt_for('--brief', 'a sequence diagram', plan)

      expect(prompt).to include("## Brief\n\na sequence diagram\n")
      expect(prompt).not_to include('No brief was given.')
    end

    it 'accepts -b, --brief=, and a brief after the file' do
      [['-b', 'a gif', plan], ['--brief=a gif', plan], [plan, '--brief', 'a gif']].each do |args|
        expect(prompt_for(*args)).to include("## Brief\n\na gif\n")
      end
    end

    it 'reads the brief from stdin for "-" and strips trailing whitespace' do
      stdin.string = "a slide\ndeck\n\n"

      expect(prompt_for('--brief', '-', plan)).to include("## Brief\n\na slide\ndeck\n\n## Rules")
    end

    it 'treats a blank brief as no brief' do
      ['', '  '].each do |brief|
        expect(prompt_for('--brief', brief, plan)).to include('No brief was given.')
      end
    end

    it 'treats empty stdin as no brief' do
      expect(prompt_for('--brief', '-', plan)).to include('No brief was given.')
    end
  end

  describe 'errors' do
    it 'raises a usage error for no file, two files, an unknown flag or a missing -b value' do
      [[], [plan, plan], ['--bogus', plan], [plan, '-b']].each do |args|
        expect { command.call(args) }.to raise_error(Planner::UsageError)
      end
    end

    it 'rejects a file that cannot be summarised' do # rubocop:disable RSpec/ExampleLength
      %w[notes.md ITERATION-002.md PLAN-002-a.md SUMMARY-002.md].each do |name|
        File.write("docs/plans/x/#{name}", '')

        expect { command.call(["docs/plans/x/#{name}"]) }
          .to raise_error(Planner::Error,
                          "docs/plans/x/#{name} is not a PLAN-<N>.md, REVIEW-<N>.md or FINDINGS-<N>.md file")
      end
    end

    it 'rejects a missing source file' do
      expect { command.call(['docs/plans/x/PLAN-009.md']) }
        .to raise_error(Planner::Error, 'docs/plans/x/PLAN-009.md does not exist')
    end

    it 'checks the name before the existence' do
      expect { command.call(['nope.md']) }
        .to raise_error(Planner::Error, 'nope.md is not a PLAN-<N>.md, REVIEW-<N>.md or FINDINGS-<N>.md file')
    end
  end
end
