# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../no_request_in_before'

RSpec.describe RuboCop::Cop::Planner::NoRequestInBefore, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/NoRequestInBefore')
        .except('Include')
  end

  it 'flags get and post in before' do
    expect_offense(<<~RUBY)
      before do
        get :index
        ^^^^^^^^^^ Make the request in the example, not in `before`.
        post "/widgets"
        ^^^^^^^^^^^^^^^ Make the request in the example, not in `before`.
      end
    RUBY
  end

  it 'does not flag headers or sign_in in before' do
    expect_no_offenses(<<~RUBY)
      before do
        request.headers['X-Token'] = 'abc'
        sign_in user
      end
    RUBY
  end

  it 'does not flag a request inside an example' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index
      end
    RUBY
  end
end
