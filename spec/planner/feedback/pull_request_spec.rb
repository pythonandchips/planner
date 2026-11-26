# frozen_string_literal: true

RSpec.describe Planner::Feedback::PullRequest, :aggregate_failures do
  let(:url) { 'https://github.com/o/r/pull/42' }
  let(:view) { { 'number' => 42, 'title' => 'Add login', 'url' => url } }
  let(:threads) { [] }
  let(:reviews) { [] }
  let(:comments) { [] }
  let(:fake_gh) { FakeGh.new(view:, graphql: graphql(threads:, reviews:, comments:)) }
  let(:feedback) { described_class.fetch(fake_gh, '42') }

  def page(nodes, next_page: false)
    { 'pageInfo' => { 'hasNextPage' => next_page }, 'nodes' => nodes }
  end

  def author(login) = login && { 'login' => login }

  def comment(login, body, state: 'SUBMITTED')
    { 'author' => author(login), 'body' => body, 'state' => state }
  end

  def node(login, body) = { 'author' => author(login), 'body' => body }

  def review(login, state, body) = { 'author' => author(login), 'state' => state, 'body' => body }

  def thread(path:, line:, comments:, resolved: false, outdated: false, more: false)
    { 'isResolved' => resolved, 'isOutdated' => outdated, 'path' => path, 'line' => line,
      'comments' => page(comments, next_page: more) }
  end

  def graphql(threads: [], reviews: [], comments: [], more_threads: false)
    pull = { 'reviewThreads' => page(threads, next_page: more_threads), 'reviews' => page(reviews),
             'comments' => page(comments) }
    { 'data' => { 'repository' => { 'pullRequest' => pull } } }
  end

  context 'with every kind of comment' do
    let(:threads) do
      [thread(path: 'lib/foo.rb', line: 12, comments: [comment('alice', 'Rename this method.'),
                                                       comment('bob', 'Agreed.')]),
       thread(path: 'README.md', line: nil, comments: [comment('carol', 'Add a usage section.')])]
    end
    let(:reviews) { [review('alice', 'CHANGES_REQUESTED', "Needs specs.\r\n\r\nSee lib/foo.rb.")] }
    let(:comments) { [node(nil, 'Can we update the README?')] }
    let(:expected_markdown) do
      <<~MARKDOWN
        # Review feedback — PR #42: Add login

        https://github.com/o/r/pull/42

        Address the review comments below.

        ## Inline comments

        ### README.md

        - **carol**:
          > Add a usage section.

        ### lib/foo.rb:12

        - **alice**:
          > Rename this method.
        - **bob**:
          > Agreed.

        ## Reviews

        - **alice** (Changes requested):
          > Needs specs.
          >
          > See lib/foo.rb.

        ## Conversation

        - **ghost**:
          > Can we update the README?
      MARKDOWN
    end

    it 'renders the feedback as markdown' do
      expect(feedback.to_markdown).to eq(expected_markdown)
    end
  end

  it 'asks gh for the pull request, then for its comments' do
    feedback

    expect(fake_gh.calls.first).to eq(['pr', 'view', '42', '--json', 'number,title,url'])
    expect(fake_gh.calls.last.first(4)).to eq(['api', 'graphql', '--hostname', 'github.com'])
    expect(fake_gh.calls.last).to include('owner=o', 'name=r', 'number=42')
  end

  context 'with a GitHub Enterprise URL' do
    let(:url) { 'https://git.example.com/o/r/pull/42' }

    it 'passes the host as --hostname' do
      feedback

      expect(fake_gh.calls.last.each_cons(2)).to include(['--hostname', 'git.example.com'])
    end
  end

  context 'with resolved and outdated threads' do
    let(:threads) do
      [thread(path: 'a.rb', line: 1, comments: [comment('a', 'x')], resolved: true),
       thread(path: 'b.rb', line: 1, comments: [comment('a', 'x')], outdated: true)]
    end

    it 'leaves them out' do
      expect(feedback).to be_empty
    end
  end

  context 'with pending, blank, approved and dismissed reviews' do
    let(:reviews) do
      [review('a', 'PENDING', 'draft'), review('b', 'COMMENTED', "  \n"), review('c', 'APPROVED', 'LGTM'),
       review('d', 'DISMISSED', 'Stale')]
    end

    it 'keeps only the submitted reviews with a body, labelled' do
      expect(feedback.to_markdown).to include('- **c** (Approved):', '- **d** (Dismissed):')
      expect(feedback.to_markdown).not_to match(/\*\*[ab]\*\*/)
    end
  end

  context 'with blank comments' do
    let(:threads) do
      [thread(path: 'a.rb', line: 1, comments: [comment('a', ' ')]),
       thread(path: 'b.rb', line: 2, comments: [comment('a', ''), comment('b', 'Keep')])]
    end
    let(:comments) { [node('c', "\n")] }

    it 'leaves them out and drops a thread with none left' do
      expect(feedback.to_markdown).to include('### b.rb:2', '- **b**:')
      expect(feedback.to_markdown).not_to include('a.rb', '- **a**', '- **c**')
    end
  end

  context 'with pending thread comments' do
    let(:threads) do
      [thread(path: 'a.rb', line: 1, comments: [comment('a', 'draft', state: 'PENDING')]),
       thread(path: 'b.rb', line: 2, comments: [comment('b', 'draft', state: 'PENDING'),
                                                comment('c', 'sent')])]
    end

    it 'leaves them out, keeping submitted ones, and drops a thread with none left' do
      expect(feedback.to_markdown).to include('### b.rb:2', '- **c**:')
      expect(feedback.to_markdown).not_to include('a.rb', '- **a**', '- **b**')
    end
  end

  context 'with only conversation comments' do
    let(:comments) { [node('a', 'Hi')] }

    it 'leaves out the empty sections' do
      expect(feedback.to_markdown).to include('## Conversation')
      expect(feedback.to_markdown).not_to include('## Inline comments', '## Reviews')
    end
  end

  context 'with everything resolved, outdated, pending or blank' do
    let(:threads) { [thread(path: 'a.rb', line: 1, comments: [comment('a', 'x')], resolved: true)] }
    let(:reviews) { [review('a', 'PENDING', 'x')] }
    let(:comments) { [node('a', ' ')] }

    it 'is empty' do
      expect(feedback).to be_empty
    end
  end

  context 'when reviewThreads has another page' do
    let(:fake_gh) { FakeGh.new(view:, graphql: graphql(more_threads: true)) }

    it 'raises' do
      expect { feedback }.to raise_error(Planner::Error, /42 has more than 100 review threads/)
    end
  end

  context 'when one thread has more comments than a page' do
    let(:threads) { [thread(path: 'a.rb', line: 1, comments: [comment('a', 'x')], more: true)] }

    it 'raises' do
      expect { feedback }.to raise_error(Planner::Error, /42 has more than 100 review threads/)
    end
  end

  context 'with an unexpected URL' do
    let(:url) { 'nonsense' }

    it 'raises' do
      expect { feedback }.to raise_error(Planner::Error, 'gh returned an unexpected pull request URL: nonsense')
    end
  end
end
