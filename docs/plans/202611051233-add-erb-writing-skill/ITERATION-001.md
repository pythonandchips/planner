I want to add a new skill for code quality. In another session I had claude draft the following

```
Before (don't do this)

<%= tag.div(
  class: "chart-section chart-frame",
  aria: { hidden: ("true" if chart) },
  data: {
    testid: "widgets-chart-frame",
    controller: ("widgets-chart" if chart),
  }
) do %>
  <% if chart %>
    <div data-widgets-chart-target="chart"></div>

    <template id="widgets-chart-data"><%= chart.to_json %></template>
  <% end %>
<% end %>

if chart appears three times. To see what renders when chart is nil, you have to read every one.

After (do this)

<% if chart %>
  <div
    class="chart-section chart-frame"
    aria-hidden="true"
    data-testid="widgets-chart-frame"
    data-controller="widgets-chart"
  >
    <div data-widgets-chart-target="chart"></div>

    <template id="widgets-chart-data"><%= chart.to_json %></template>
  </div>
<% else %>
  <div class="chart-section chart-frame" data-testid="widgets-chart-frame"></div>
<% end %>

The condition is tested once, and each branch is the complete markup for that case. The class and testid are repeated in both branches. The rule accepts that cost in exchange for being able to read each case top to bottom.
```

Create me the news
