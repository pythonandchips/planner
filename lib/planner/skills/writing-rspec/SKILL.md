---
name: writing-rspec
description: 'Rules for writing or editing RSpec specs. Use this skill whenever you add or change describe, context or it blocks or expectations in a spec file: descriptions say what the code does, in the present tense without "should", and expectations are separate lines rather than compound .and matchers.'
---

# Writing RSpec

Follow these two rules whenever you write or edit a spec. They apply only to the
descriptions and expectations you write or change. Do not rewrite existing specs that the
task does not otherwise touch.

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

## Before you finish

Check each description and expectation you wrote or changed against the rules above and fix
any that break them.
