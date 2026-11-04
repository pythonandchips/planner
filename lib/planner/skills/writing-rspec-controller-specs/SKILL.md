---
name: writing-rspec-controller-specs
description: 'Rules for writing or editing Rails controller or request specs, used alongside the writing-rspec skill. Use this skill whenever you add or change examples in a spec under spec/controllers or spec/requests: records are created with let!, the request is the first line of the example, the response status is checked first, and every expectation about one request lives in one example.'
---

# Writing RSpec controller specs

These rules apply to controller specs (`spec/controllers`, `type: :controller`) and request
specs (`spec/requests`, `type: :request`) that you write or edit. Do not rewrite existing
specs that the task does not otherwise touch.

Also follow the `writing-rspec` skill. Where the two differ, this skill wins for controller
and request specs. The one difference is that these examples are not tagged
`:aggregate_failures`: the status check comes first, and if it fails, the example stops
before the other expectations run.

## Setup

Creating records in `before` and then making the request there too forces every `it` to
rebuild the records and hides which action an example runs.

- Create the records the request needs with `let!`, or with `let` when an example
  references the value and it doesn't have to exist before the request. Never create
  records in `before`.
- `before` only prepares the request: headers, sign-in, stubs. It never makes the request.
  Signing in a lazy `let` record there, as in `before { sign_in user }` with
  `let(:user)`, is allowed.

## The example

- Make the request (`get :index`, `post "/path"`, ...) on the first line of the `it`, so it
  is clear which action the example runs. Follow it with a blank line.
- The first expectation checks the response status with
  `expect(response).to have_http_status(...)`, using whatever status fits (`:success`,
  `:redirect`, `:not_found`, a number, ...). A wrong status means the other expectations
  are meaningless, so this check gates them. Follow it with a blank line, then the other
  expectations.
- Put every expectation about the same request in one `it`. This creates the records once
  instead of once per example. Use separate `it`s only when the setup or request differs,
  and put those in separate contexts.

```ruby
# Bad
  context "when requested from a turbo frame with widget activity" do
    let(:widget) { project.widgets.first }

    before do
      create(:widget_sale, widget: widget, amount: 150, dated_on: Date.yesterday)
      create(:widget_review, widget: widget, marked_for_review: true)

      request.headers["Turbo-Frame"] = "widgets-chart"
      get :index
    end

    it "assigns metrics for all widgets" do
      expect(assigns(:metrics)).to be_a(Widgets::Metrics)
    end

    it "calculates the total sales" do
      expect(assigns(:metrics).total_sales).to eq("150")
    end

    it "counts the widgets for review" do
      expect(assigns(:metrics).total_for_review).to eq("1")
    end

    it "counts the unassigned widgets" do
      expect(assigns(:metrics).total_unassigned).to eq("1")
    end
  end

# Good
  context "when requested from a turbo frame with widget activity" do
    let(:widget) { project.widgets.first }
    let!(:widget_sale) { create(:widget_sale, widget: widget, amount: 150, dated_on: Date.yesterday) }
    let!(:widget_review) { create(:widget_review, widget: widget, marked_for_review: true) }

    before do
      request.headers["Turbo-Frame"] = "widgets-chart"
    end

    it "displays the metrics for all widgets" do
      get :index

      expect(response).to have_http_status(:success)

      expect(assigns(:metrics)).to be_a(Widgets::Metrics)
      expect(assigns(:metrics).total_sales).to eq("150")
      expect(assigns(:metrics).total_for_review).to eq("1")
      expect(assigns(:metrics).total_unassigned).to eq("1")
    end
  end
```

## Before you finish

Check each controller or request example you wrote or changed against the rules above and
fix any that break them.
