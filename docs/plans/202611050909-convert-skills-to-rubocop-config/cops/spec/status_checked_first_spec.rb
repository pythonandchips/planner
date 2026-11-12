# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../status_checked_first'

RSpec.describe RuboCop::Cop::Planner::StatusCheckedFirst, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/StatusCheckedFirst')
        .except('Include')
  end

  it 'does not flag a status check followed by a blank line and other expectations' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index

        expect(response).to have_http_status(:ok)

        expect(assigns(:widgets)).to eq([])
      end
    RUBY
  end

  it 'does not flag a status check that is the last statement' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index

        expect(response).to have_http_status(:ok)
      end
    RUBY
  end

  it 'does not flag a non-expectation line before the status check' do
    expect_no_offenses(<<~RUBY)
      it 'shows widgets' do
        get :index
        body = response.body

        expect(response).to have_http_status(:ok)
      end
    RUBY
  end

  it 'flags a first expectation that is not the status check' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
        get :index

        expect(assigns(:widgets)).to eq([])
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Make the first expectation `expect(response).to have_http_status(...)`.
        expect(response).to have_http_status(:ok)
      end
    RUBY
  end

  it 'flags a missing blank line after the status check' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
        get :index

        expect(response).to have_http_status(:ok)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^ Follow the status check with a blank line.
        expect(assigns(:widgets)).to eq([])
      end
    RUBY
  end

  it 'flags an example with no expectations' do
    expect_offense(<<~RUBY)
      it 'shows widgets' do
      ^^^^^^^^^^^^^^^^^^ Make the first expectation `expect(response).to have_http_status(...)`.
        get :index
      end
    RUBY
  end
end
