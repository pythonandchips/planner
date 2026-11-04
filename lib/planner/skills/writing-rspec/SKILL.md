---
name: writing-rspec
description: 'Rules for writing or editing RSpec specs. Use this skill whenever you add or change describe, context or it blocks or expectations in a spec file: descriptions say what the code does, in the present tense without "should", and expectations are separate lines rather than compound .and matchers, and objects are set up with let! or let rather than in before blocks.'
---

# Writing RSpec

Follow these four rules whenever you write or edit a spec. They apply only to the
descriptions, expectations, setup and class references you write or change. Do not rewrite
existing specs that the task does not otherwise touch.

## Descriptions say what the code does, not how

A spec description is documentation. Readers use it to learn what the code does for its
caller, so it should survive a refactor that keeps the behaviour the same.

- Every `describe`, `context`, `it`, `specify` and `example` string says what the caller or
  user observes: the value returned, the output, the error raised or the side effect.
- Do not name private methods, internal classes, data structures, or how the result is
  computed.
- Exception: you may group examples under `describe '#method'` (or `'.method'`) naming the
  method under test. `describe SomeClass` with a constant is also fine.
- Write in the present tense without "should": `it 'returns the total'`, not
  `it 'should return the total'`.

```ruby
# Bad
it 'calls #apply_discount and memoizes @total' do

# Good
it 'returns the total after the discount' do
```

## No compound matchers

A compound matcher stops at the first failing half, so you only learn about one problem at
a time.

- Do not chain expectations with `.and` or `&`.
- Instead, write one `expect` per line in the same example and tag the example or group
  `:aggregate_failures` so every failure is reported.

```ruby
# Bad
expect(out).to start_with('Done').and include('3 files')

# Good
it 'reports the files it wrote', :aggregate_failures do
  expect(out).to start_with('Done')
  expect(out).to include('3 files')
end
```

## Set up objects with let, not before

Objects created in `before` have no name, so examples can't refer to them and readers can't
see what each example depends on.

- Create every object the examples need with `let!`, or with `let` when an example
  references the value and it doesn't have to exist before the example runs. This covers
  FactoryBot (`create`, `create_list`, `build`, `build_stubbed`, ...), objects made by hand
  (`Widget.new`, `Widget.create`, ...) and test doubles (`double`,
  `instance_double`, `spy`, ...). Never create them in `before`.
- Several objects of the same kind can each have their own `let!` or share one `let!` that
  returns an array. Either is fine.
- `before` only does setup that doesn't instantiate objects: stubs (`allow(...).to receive`,
  `expect(...).to receive`), sign-in, headers, time travel, config.
- Write hooks as plain `before do ... end`. Never use `before(:all)` or `before(:context)`,
  and don't write the `:each` or `:example` argument.

```ruby
# Bad
RSpec.describe Widgets::WidgetMetrics do
  subject(:metrics) { Widgets::WidgetMetrics.new(widget: second_widget) }

  let(:project) { create(:project) }
  let(:first_widget) { project.widgets.first }
  let(:second_widget) { create(:widget, project: project) }

  before do
    create(:widget_sale, widget: first_widget, amount: 150, dated_on: Date.yesterday)
    create(:widget_review, widget: first_widget, marked_for_review: true)

    create(:widget_sale, widget: second_widget, amount: 40, dated_on: Date.yesterday)
    create(:widget_review, widget: second_widget, marked_for_review: true)
  end

  describe "#total_sales" do
    it "returns the total sales of the widget only" do
      expect(metrics.total_sales).to eq("140")
    end
  end
end

# Good
RSpec.describe Widgets::WidgetMetrics do
  subject(:metrics) { Widgets::WidgetMetrics.new(widget: second_widget) }

  let(:project) { create(:project) }
  let(:first_widget) { project.widgets.first }
  let(:second_widget) { create(:widget, project: project) }
  let!(:widget_sales) do
    [
      create(:widget_sale, widget: first_widget, amount: 150, dated_on: Date.yesterday),
      create(:widget_sale, widget: second_widget, amount: 40, dated_on: Date.yesterday)
    ]
  end
  let!(:widget_reviews) do
    [
      create(:widget_review, widget: second_widget, marked_for_review: true),
      create(:widget_review, widget: first_widget, marked_for_review: true)
    ]
  end

  describe "#total_sales" do
    it "returns the total sales of the widget only" do
      expect(metrics.total_sales).to eq("140")
    end
  end
end
```

## Name the class under test, not described_class

The full class name shows which class an example uses without scrolling up to the
`describe` line, and it can be searched for. `described_class` hides both.

- Never use `described_class`. Write the class's fully qualified name instead, as in the
  `RSpec.describe` line: `Widgets::WidgetMetrics`, not `WidgetMetrics` and not
  `::Widgets::WidgetMetrics`. This covers every use: `subject`, `let`, inside
  examples, constants (`Widgets::WidgetMetrics::LIMIT`), doubles
  (`instance_double(Widgets::WidgetMetrics)`) and message expectations.
- Exception: inside `shared_examples` or `shared_context` used by more than one class,
  `described_class` is allowed. If the shared block is used by only one class, write the
  full name.

```ruby
# Bad
subject(:metrics) { described_class.new(widget: widget) }

# Good
subject(:metrics) { Widgets::WidgetMetrics.new(widget: widget) }
```

## Before you finish

Check each description, expectation, piece of setup and class reference you wrote or
changed against the rules above and fix any that break them.
