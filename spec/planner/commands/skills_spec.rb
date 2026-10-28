# frozen_string_literal: true

RSpec.describe Planner::Commands::Skills, :aggregate_failures do
  let(:stdin) { StringIO.new }
  let(:stdout) { StringIO.new }
  let(:context) do
    Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd / 'home', skills_dir: Pathname.pwd / 'skills',
                         agent: FakeAgent.new, stdin:, stdout:, clock: -> { Time.now })
  end

  def run(*args) = described_class.new(context).call(args)

  def write_skill(slug, description = "Does #{slug}", *extra)
    FileUtils.mkdir_p("skills/#{slug}")
    File.write("skills/#{slug}/SKILL.md", "---\nname: #{slug}\ndescription: #{description}\n---\nBody\n")
    extra.each do |file|
      FileUtils.mkdir_p(File.dirname("skills/#{slug}/#{file}"))
      File.write("skills/#{slug}/#{file}", "#{file}\n")
    end
  end

  def clear_stdout
    stdout.truncate(0)
    stdout.rewind
  end

  def tree(dir)
    Dir.glob('**/*', File::FNM_DOTMATCH, base: dir).select { |f| File.file?("#{dir}/#{f}") }.sort.to_h do |f|
      [f, File.read("#{dir}/#{f}")]
    end
  end

  describe 'dispatching' do
    it 'raises UsageError with the skills usage for bad usage' do
      [[], ['bogus'], %w[list extra], %w[install --bogus], %w[install extra]].each do |args|
        expect { run(*args) }.to raise_error(Planner::UsageError) { |e| expect(e.usage).to eq(described_class::USAGE) }
      end
    end
  end

  describe 'list' do
    it 'says so when there are no skills' do
      run('list')

      expect(stdout.string).to eq("No skills available.\n")
    end

    it 'prints each skill with its description' do
      write_skill('yarn', 'Run yarn')
      write_skill('git-commit', 'How to write commits')

      run('list')

      expect(stdout.string).to eq("git-commit  How to write commits\nyarn        Run yarn\n")
    end

    it 'prints just the slug for a blank description' do
      write_skill('yarn', '')

      run('list')

      expect(stdout.string).to eq("yarn\n")
    end
  end

  describe 'install' do
    before do
      write_skill('yarn', 'Run yarn')
      write_skill('git-commit', 'How to write commits', 'scripts/x.sh')
    end

    it 'says so and changes nothing when there are no skills' do
      FileUtils.rm_rf('skills')

      run('install')
      run('install', '--only', 'nope')

      expect(stdout.string).to eq("No skills available.\nNo skills available.\n")
      expect(File).not_to exist('.claude')
    end

    it 'copies every skill into an empty project' do
      run('install')

      expect(tree('.claude/skills/git-commit')).to eq(tree('skills/git-commit')).and include('scripts/x.sh')
      expect(tree('.claude/skills/yarn')).to eq(tree('skills/yarn'))
    end

    it 'prints one line per installed skill and no prompt' do
      run('install')

      expect(stdout.string).to eq(
        "installed git-commit -> .claude/skills/git-commit\ninstalled yarn -> .claude/skills/yarn\n"
      )
    end

    it 'installs into the home directory with --global' do
      run('install', '--global')

      expect(tree('home/.claude/skills/yarn')).to eq(tree('skills/yarn'))
      expect(File).not_to exist('.claude')
      expect(stdout.string).to include('installed yarn -> ~/.claude/skills/yarn')
    end

    {
      '--only yarn' => %w[yarn],
      '--only=yarn' => %w[yarn],
      '--only git-commit --only yarn' => %w[git-commit yarn]
    }.each do |flags, slugs|
      it "selects #{slugs.join(' and ')} with #{flags}" do
        run('install', *flags.split)

        expect(Dir.children('.claude/skills').sort).to eq(slugs)
      end
    end

    it 'rejects unknown --only slugs before changing anything' do
      expect { run('install', '--only', 'yarn,nope,zzz') }
        .to raise_error(Planner::Error, 'Unknown skill: nope, zzz')
      expect(File).not_to exist('.claude')
    end

    context 'with an identical installed skill' do
      before do
        run('install', '--only', 'yarn')
        File.utime(Time.at(0), Time.at(0), '.claude/skills/yarn/SKILL.md')
        clear_stdout
      end

      it 'leaves it alone without asking' do
        run('install', '--only', 'yarn')

        expect(stdout.string).to eq("unchanged yarn\n")
        expect(File.mtime('.claude/skills/yarn/SKILL.md')).to eq(Time.at(0))
      end
    end

    context 'with a changed installed skill' do
      before do
        run('install', '--only', 'git-commit')
        File.write('.claude/skills/git-commit/extra.md', 'extra')
        clear_stdout
      end

      let(:prompt) do
        "These skills already exist in .claude/skills and will be replaced:\n  git-commit\nOverwrite? [y/N] "
      end

      ["y\n", "YES\n", " yes \n"].each do |answer|
        it "replaces it after #{answer.inspect}" do
          stdin.string = answer

          run('install')

          expect(stdout.string).to start_with(prompt).and include('installed git-commit -> .claude/skills/git-commit')
          expect(tree('.claude/skills/git-commit')).to eq(tree('skills/git-commit'))
        end
      end

      ["n\n", "\n", ''].each do |answer|
        it "installs nothing after #{answer.inspect}" do
          stdin.string = answer

          expect { run('install') }.to raise_error(Planner::Error, 'Install cancelled')
          expect(File).to exist('.claude/skills/git-commit/extra.md')
          expect(File).not_to exist('.claude/skills/yarn')
        end
      end

      it 'lists only changed existing skills in the prompt' do
        stdin.string = "y\n"

        run('install')

        expect(stdout.string.lines.grep(/\A  /)).to eq(["  git-commit\n"])
      end
    end
  end
end
