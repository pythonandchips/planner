The agent is producing the following rspec code 

```
RSpec.describe Widgets::WidgetMetrics do
  subject(:metrics) { described_class.new(widget: second_widget) }

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

  describe "#total_for_review" do
    it "counts the widgets for review on the widget only" do
      expect(metrics.total_for_review).to eq("1")
    end
  end

  describe "#total_unassigned" do
    it "counts the unassigned widgets on the widget only" do
      expect(metrics.total_unassigned).to eq("1")
    end
  end
end
```

However the `before` block is not expected to have `create` in them. It need to be written as this with the entites created in `let!` blocks

```
RSpec.describe Widgets::WidgetMetrics do
  subject(:metrics) { described_class.new(widget: second_widget) }

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

  describe "#total_for_review" do
    it "counts the widgets for review on the widget only" do
      expect(metrics.total_for_review).to eq("1")
    end
  end

  describe "#total_unassigned" do
    it "counts the unassigned widgets on the widget only" do
      expect(metrics.total_unassigned).to eq("1")
    end
  end
end
```

The important part is using `let!` instead of putting all the items in a `before` block. 
This is the same as was added to the `writing-rspec-controler-specs` skill.

Update the `writing-rspec` skill.
You can refactor this out of the `writing-rspec-controler-specs` if it is required
