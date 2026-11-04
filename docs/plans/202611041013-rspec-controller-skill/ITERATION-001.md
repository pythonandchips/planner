When writing rspec tests the agents have been writing them in this form. This is inefficient for a controller test 

```
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
```

The tests instead must be laid out like this

```
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

This is more efficent as the test only has to create the database records onces.
It also makes it clear what the action is running as it is first line of the `it` 
Finally a controller spec must check the response code first to ensure the response was correct.

Create a new skill for rspec controller spec. This will be used in addition to the existing rspec skill but is specific rules for controller specs
Use the `skill-creator` sill to help build the skill as part of the run stage
This skill will be installed by `planner`
