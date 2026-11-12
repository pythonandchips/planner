# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../no_compound_matcher'

RSpec.describe RuboCop::Cop::Planner::NoCompoundMatcher, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/NoCompoundMatcher')
        .except('Include')
  end

  it 'flags .and' do
    expect_offense(<<~RUBY)
      expect(out).to start_with('a').and include('b')
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.
    RUBY
  end

  it 'flags &' do
    expect_offense(<<~RUBY)
      expect(out).to start_with('a') & include('b')
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.
    RUBY
  end

  it 'flags .and after not_to' do
    expect_offense(<<~RUBY)
      expect(out).not_to start_with('a').and include('b')
                         ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.
    RUBY
  end

  it 'flags .and with is_expected' do
    expect_offense(<<~RUBY)
      is_expected.to start_with('a').and include('b')
                     ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.
    RUBY
  end

  it 'flags .and with a block expectation' do
    expect_offense(<<~RUBY)
      expect { run }.to change { a }.and change { b }
                        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.
    RUBY
  end

  it 'does not flag .or or |' do
    expect_no_offenses(<<~RUBY)
      expect(out).to start_with('a').or include('b')
      expect(out).to start_with('a') | include('b')
    RUBY
  end

  it 'does not flag two separate expect lines' do
    expect_no_offenses(<<~RUBY)
      expect(out).to start_with('a')
      expect(out).to include('b')
    RUBY
  end

  it 'does not flag a stub that uses and_return' do
    expect_no_offenses(<<~RUBY)
      allow(x).to receive(:y).and_return(1)
    RUBY
  end
end
