# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../request_first'

RSpec.describe RuboCop::Cop::Planner::RequestFirst, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/RequestFirst')
        .except('Include')
  end

  it 'does not flag a request, a blank line, then an expectation' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index

        expect(response).to have_http_status(:ok)
      end
    RUBY
  end

  it 'does not flag an example that is only the request' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index
      end
    RUBY
  end

  it 'flags an expectation before the request' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
        expect(x).to eq(1)
        ^^^^^^^^^^^^^^^^^^ Make the request on the first line of the example.
        get :index
      end
    RUBY
  end

  it 'flags a missing blank line after the request' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
        get :index
        ^^^^^^^^^^ Follow the request with a blank line.
        expect(response).to have_http_status(:ok)
      end
    RUBY
  end

  it 'flags an empty example' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
      ^^^^^^^^^^^^^^^^^^ Make the request on the first line of the example.
      end
    RUBY
  end

  it 'flags a one-line example' do
    expect_offense(<<~RUBY)
      it { is_expected.to be_ok }
           ^^^^^^^^^^^^^^^^^^^^ Make the request on the first line of the example.
    RUBY
  end

  it 'applies to specify' do
    expect_offense(<<~RUBY)
      specify do
        expect(x).to eq(1)
        ^^^^^^^^^^^^^^^^^^ Make the request on the first line of the example.
      end
    RUBY
  end

  it 'applies to example' do
    expect_offense(<<~RUBY)
      example do
        expect(x).to eq(1)
        ^^^^^^^^^^^^^^^^^^ Make the request on the first line of the example.
      end
    RUBY
  end
end
