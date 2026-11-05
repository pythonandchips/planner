---
name: writing-erb
description: 'Rules for writing or editing ERB view templates (views, partials, layouts). Use this skill whenever you write or change an .erb file: when the same condition would be tested more than once in an element and its contents, test it once with if/else and write each branch as the complete markup for that case.'
---

# Writing ERB

Follow this rule whenever you write or edit an ERB view template (`.erb` files: views,
partials, layouts). It applies only to the templates you write or edit. Do not rewrite
existing markup that the task does not otherwise touch.

## Test a condition once

When the same condition is tested in several places, the reader has to check each one to
work out what renders in each case.

- When the same condition would be tested two or more times within one element and its
  contents (in attributes such as `("true" if chart)`, in `<% if chart %>` blocks inside it,
  or both), test it once with `<% if %>` / `<% else %>` around the element, and write each
  branch as the complete markup for that case.
- Repeating attributes that both branches share (such as `class`) is accepted. The cost is
  worth being able to read each case top to bottom.
- A condition tested only once, such as a single conditional CSS class, stays inline. Do not
  split it into `if`/`else`.
- Plain HTML tags and tag helpers (`tag.div`, `content_tag`) are both fine in the branches.
  Keep the style the file already uses; the rule is only about where the condition is
  tested.

Bad:

```erb
<%= tag.div(
  class: "chart",
  aria: { hidden: ("true" if chart) },
  data: { controller: ("chart" if chart) }
) do %>
  <% if chart %>
    <template id="chart-data"><%= chart.to_json %></template>
  <% end %>
<% end %>
```

`if chart` appears three times. To see what renders when `chart` is nil, you have to read
every one.

Good:

```erb
<% if chart %>
  <div class="chart" aria-hidden="true" data-controller="chart">
    <template id="chart-data"><%= chart.to_json %></template>
  </div>
<% else %>
  <div class="chart"></div>
<% end %>
```

The condition is tested once, and each branch is the complete markup for that case. The
class is repeated in both branches. The rule accepts that cost in exchange for being able to
read each case top to bottom.

## Before you finish

Check each element you wrote or changed in an ERB template for a condition tested more than
once, and fix any that break the rule.
