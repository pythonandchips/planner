# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../no_objects_in_before'

RSpec.describe RuboCop::Cop::Planner::NoObjectsInBefore, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/NoObjectsInBefore')
        .except('Include')
  end

  it 'flags create, build_stubbed and double in before' do
    expect_offense(<<~RUBY)
      before do
        create(:widget)
        ^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
        build_stubbed(:widget)
        ^^^^^^^^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
        double('widget')
        ^^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
      end
    RUBY
  end

  it 'flags constructors on constants' do
    expect_offense(<<~RUBY)
      before do
        Widget.new
        ^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
        Widgets::Widget.create
        ^^^^^^^^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
        FactoryBot.create(:widget)
        ^^^^^^^^^^^^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
      end
    RUBY
  end

  it 'flags create in prepend_before' do
    expect_offense(<<~RUBY)
      prepend_before do
        create(:widget)
        ^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
      end
    RUBY
  end

  it 'flags create in append_before' do
    expect_offense(<<~RUBY)
      append_before do
        create(:widget)
        ^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
      end
    RUBY
  end

  it 'flags build inside and_return' do
    expect_offense(<<~RUBY)
      before do
        allow(x).to receive(:y).and_return(build(:z))
                                           ^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
      end
    RUBY
  end

  it 'does not flag stubs or sign_in' do
    expect_no_offenses(<<~RUBY)
      before do
        allow(x).to receive(:y).and_return(1)
        sign_in user
      end
    RUBY
  end

  it 'does not flag arguments of travel_to' do
    expect_no_offenses(<<~RUBY)
      before do
        travel_to Time.new(2024, 1, 1)
        travel_to Date.new(2024, 1, 1)
      end
    RUBY
  end

  it 'flags create inside the block of travel_to' do
    expect_offense(<<~RUBY)
      before do
        travel_to(Time.new(2024, 1, 1)) do
          create(:widget)
          ^^^^^^^^^^^^^^^ Create objects with `let!` or `let`, not in `before`.
        end
      end
    RUBY
  end

  it 'does not flag create in let!, after or around' do
    expect_no_offenses(<<~RUBY)
      let!(:widget) { create(:widget) }
      after { create(:widget) }
      around { |example| create(:widget) }
    RUBY
  end

  it 'does not flag config.before' do
    expect_no_offenses(<<~RUBY)
      config.before { create(:x) }
    RUBY
  end
end
