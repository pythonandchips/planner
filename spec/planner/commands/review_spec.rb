# frozen_string_literal: true

RSpec.describe Planner::Commands::Review, :aggregate_failures do
  subject(:command) { described_class.new(context) }

  let(:agent) { FakeAgent.new }
  let(:stdin) { StringIO.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, agent:, stdin:, stdout: StringIO.new, clock: -> { Time.now })
  end
  let(:plan) { 'docs/plans/x/PLAN-001.md' }

  def call = agent.calls.first

  before do
    FileUtils.mkdir_p('docs/plans/x')
    File.write(plan, "the plan\n")
  end

  it "uses the agent's default model" do
    command.call([plan])

    expect(agent.calls.size).to eq(1)
    expect(call[0]).to eq(:review)
    expect(call[2]).to eq('default-review-model')
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

  describe 'the report file' do
    it 'is REVIEW-<NNN>.md next to the plan' do
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/REVIEW-001.md')
    end

    it 'gets -a when the review exists' do
      File.write('docs/plans/x/REVIEW-001.md', '')
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/REVIEW-001-a.md')
    end

    it 'gets -b when the review and -a exist' do
      %w[REVIEW-001.md REVIEW-001-a.md].each { |name| File.write("docs/plans/x/#{name}", '') }
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/REVIEW-001-b.md')
    end

    it 'gets -aa when the review and -a to -z exist' do
      File.write('docs/plans/x/REVIEW-001.md', '')
      ('a'..'z').each { |letter| File.write("docs/plans/x/REVIEW-001-#{letter}.md", '') }
      command.call([plan])

      expect(call[3]).to eq('docs/plans/x/REVIEW-001-aa.md')
    end

    it 'zero-pads the plan number' do
      File.write('docs/plans/x/PLAN-3.md', '')
      command.call(['docs/plans/x/PLAN-3.md'])

      expect(call[3]).to eq('docs/plans/x/REVIEW-003.md')
    end
  end

  describe 'the prompt with no lens' do
    let(:prompt) do
      command.call([plan])
      call[1]
    end

    it 'starts with the review heading' do
      expect(prompt).to start_with("# Review Plan\n")
    end

    it 'names the plan, the review file and the title' do
      expect(prompt).to include('Review the plan `docs/plans/x/PLAN-001.md`', '`docs/plans/x/REVIEW-001.md`',
                                '`# REVIEW-001 — docs/plans/x/PLAN-001.md`')
    end

    it 'has the general checklist and the report sections' do
      expect(prompt).to include('Check that:', '## High-confidence findings', '## Top recommendations')
    end

    it 'has no lens section and no ERB leftovers' do
      expect(prompt).not_to include('## Lens')
      expect(prompt).not_to include('<%')
    end
  end

  describe 'the prompt with a lens' do
    def prompt_for(*args)
      agent.calls.clear
      command.call(args)
      call[1]
    end

    it 'narrows the review to the lens' do
      prompt = prompt_for('--lens', 'check security', plan)

      expect(prompt).to include('only through the lens below', "check security\n", '`## Lens`')
      expect(prompt).not_to include('Check that:')
    end

    it 'accepts -l, --lens=, and a lens after the file' do
      [['-l', 'check security', plan], ['--lens=check security', plan],
       [plan, '--lens', 'check security']].each do |args|
        expect(prompt_for(*args)).to include("check security\n", '`## Lens`')
      end
    end

    it 'reads the lens from stdin for "-" and strips trailing whitespace' do
      stdin.string = "big\ncontext\n\n"

      expect(prompt_for('--lens', '-', plan)).to include("big\ncontext\n")
    end

    it 'treats a blank lens as no lens' do
      ['', '  '].each do |lens|
        prompt = prompt_for('--lens', lens, plan)

        expect(prompt).to include('Check that:')
        expect(prompt).not_to include('## Lens')
      end
    end

    it 'treats empty stdin as no lens' do
      prompt = prompt_for('--lens', '-', plan)

      expect(prompt).to include('Check that:')
      expect(prompt).not_to include('## Lens')
    end
  end

  describe 'errors' do
    it 'raises a usage error for no file, two files, an unknown flag or a missing -l value' do
      [[], [plan, plan], ['--bogus', plan], [plan, '-l']].each do |args|
        expect { command.call(args) }.to raise_error(Planner::UsageError)
      end
    end

    it 'rejects a file that is not a PLAN-<N>.md file' do
      File.write('docs/plans/x/notes.md', '')

      expect { command.call(['docs/plans/x/notes.md']) }
        .to raise_error(Planner::Error, 'docs/plans/x/notes.md is not a PLAN-<N>.md file')
    end

    it 'rejects a missing plan file' do
      expect { command.call(['docs/plans/x/PLAN-009.md']) }
        .to raise_error(Planner::Error, 'docs/plans/x/PLAN-009.md does not exist')
    end

    it 'checks the name before the existence' do
      expect { command.call(['nope.md']) }
        .to raise_error(Planner::Error, 'nope.md is not a PLAN-<N>.md file')
    end
  end
end
