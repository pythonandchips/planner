# PLAN-002 — RuboCop config for the RSpec skill rules

Write a RuboCop config, `.rubocop.yml`, in this plan folder that checks the parts of the `writing-rspec` and
`writing-rspec-controller-specs` skills that FINDINGS-001 found can be checked statically. It configures five
existing rubocop-rspec cops and adds five custom cops in the `Planner` department, each with specs, under
`cops/` in this folder. The user will copy the config into an existing RuboCop config elsewhere. Nothing is
shipped with the gem or exposed through the CLI, the skills are unchanged, and this repo's own `.rubocop.yml`
is not touched.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Prefer existing cops over custom ones | Use existing cops configured to match the skills. Write custom cops only where no acceptable cop exists (from PLAN-001's brief, FINDINGS-001) |
| Scope | The five existing cops plus all three custom-cop areas from FINDINGS-001 (compound matchers, objects in `before`, controller example shape) |
| Location | This plan folder only. Not shipped in the gem, not available through the CLI |
| Config file name | `.rubocop.yml` in this folder |
| Config shape | A fragment the user copies into an existing RuboCop config. No `AllCops`, no `inherit_from` |
| `plugins: [rubocop-rspec]` in the file | Include it |
| Custom cop files | `cops/<cop_name>.rb`, loaded with `require:` paths relative to the config (`./cops/...`); the user adjusts them when copying |
| Custom cop department | `Planner` |
| Comments in the config | One comment line above each cop naming the skill rule it enforces. No header comments |
| `RSpec/ExampleWording` | Enabled, defaults (checks `it` only) |
| `RSpec/DescribedClass` | `EnforcedStyle: explicit`, `SkipBlocks: true` |
| `RSpec/HookArgument` | `EnforcedStyle: implicit` |
| `RSpec/BeforeAfterAll` | Enabled, defaults |
| `RSpec/MultipleExpectations` | Enabled, `Max: 1`, excluding `spec/controllers/**/*` and `spec/requests/**/*` |
| rubocop-rspec_rails (`RSpecRails/HttpStatus`) | Leave out of the config entirely |
| NoCompoundMatcher | Flags `.and` and `&` only, not `.or` or `\|` |
| NoObjectsInBefore hooks | `before`, `prepend_before`, `append_before` |
| NoObjectsInBefore creation inside stub arguments | Flag it too (e.g. `allow(x).to receive(:y).and_return(build(:z))`) |
| NoObjectsInBefore constructors on constants | `new` and `create` |
| NoObjectsInBefore time travel | The arguments of `travel_to`, `travel` and `freeze_time` are not checked (the skill allows time travel in `before`); their block bodies are |
| Method lists in custom cops | Configurable keys in `.rubocop.yml`, read with `cop_config` |
| Controller rules split | Three cops: `Planner/NoRequestInBefore`, `Planner/RequestFirst`, `Planner/StatusCheckedFirst` |
| How controller cops find controller/request specs | Path `Include` only: `spec/controllers/**/*_spec.rb`, `spec/requests/**/*_spec.rb` |
| Example blocks the controller cops check | `it`, `specify`, `example` |
| RequestFirst, example with no request | Flag it |
| Blank line after request / status check when it is the last statement | Allowed; the blank line is only required when another statement follows |
| StatusCheckedFirst position | The first top-level expectation must be `expect(response).to have_http_status(...)`; non-expectation lines may come before it |
| StatusCheckedFirst, example with no top-level expectations | Flag it |
| Autocorrect in custom cops | None |
| Custom cop specs | Yes, in `cops/spec/<cop_name>_spec.rb`, using RuboCop's `expect_offense` helpers, run explicitly |
| Cop spec example length | Keep examples short (small snippets) |
| Linting | Lint the cop files (`cops/*.rb`) with this repo's RuboCop config. Do not lint the cop specs |
| Skills | Leave both `SKILL.md` files unchanged |
| Commit | Yes |

## Files to create / change

All paths are under `docs/plans/202611050909-convert-skills-to-rubocop-config/`.

- `.rubocop.yml`: the config.
- `cops/no_compound_matcher.rb`: `Planner/NoCompoundMatcher`.
- `cops/no_objects_in_before.rb`: `Planner/NoObjectsInBefore`.
- `cops/no_request_in_before.rb`: `Planner/NoRequestInBefore`.
- `cops/request_first.rb`: `Planner/RequestFirst`.
- `cops/status_checked_first.rb`: `Planner/StatusCheckedFirst`.
- `cops/spec/no_compound_matcher_spec.rb`, `cops/spec/no_objects_in_before_spec.rb`,
  `cops/spec/no_request_in_before_spec.rb`, `cops/spec/request_first_spec.rb`,
  `cops/spec/status_checked_first_spec.rb`: one spec per cop.

No other file changes.

## Implementation

### `.rubocop.yml`

Write exactly this (the `Include`/`Exclude` paths resolve relative to the file they end up in, which is why
they are written for an app's root config):

```yaml
plugins:
  - rubocop-rspec

require:
  - ./cops/no_compound_matcher.rb
  - ./cops/no_objects_in_before.rb
  - ./cops/no_request_in_before.rb
  - ./cops/request_first.rb
  - ./cops/status_checked_first.rb

# writing-rspec: write descriptions in the present tense without "should" (checks `it` only).
RSpec/ExampleWording:
  Enabled: true

# writing-rspec: never use described_class; write the class's fully qualified name.
RSpec/DescribedClass:
  Enabled: true
  EnforcedStyle: explicit
  SkipBlocks: true

# writing-rspec: write hooks as plain `before do ... end`, without :each or :example.
RSpec/HookArgument:
  Enabled: true
  EnforcedStyle: implicit

# writing-rspec: never use before(:all) or before(:context).
RSpec/BeforeAfterAll:
  Enabled: true

# writing-rspec: one expect per line, with the example tagged :aggregate_failures (not in controller or request specs).
RSpec/MultipleExpectations:
  Enabled: true
  Max: 1
  Exclude:
    - spec/controllers/**/*
    - spec/requests/**/*

# writing-rspec: do not chain expectations with .and or &.
Planner/NoCompoundMatcher:
  Enabled: true
  Include:
    - '**/*_spec.rb'

# writing-rspec: create objects with let! or let, never in before.
Planner/NoObjectsInBefore:
  Enabled: true
  Include:
    - '**/*_spec.rb'
  CreationMethods:
    - create
    - create_list
    - build
    - build_stubbed
    - build_list
    - double
    - instance_double
    - class_double
    - spy
    - instance_spy
  ConstructorMethods:
    - new
    - create
  TimeTravelMethods:
    - travel_to
    - travel
    - freeze_time

# writing-rspec-controller-specs: before only prepares the request; it never makes it.
Planner/NoRequestInBefore:
  Enabled: true
  Include:
    - spec/controllers/**/*_spec.rb
    - spec/requests/**/*_spec.rb
  RequestMethods:
    - get
    - post
    - put
    - patch
    - delete
    - head

# writing-rspec-controller-specs: make the request on the first line of the example, followed by a blank line.
Planner/RequestFirst:
  Enabled: true
  Include:
    - spec/controllers/**/*_spec.rb
    - spec/requests/**/*_spec.rb
  RequestMethods:
    - get
    - post
    - put
    - patch
    - delete
    - head

# writing-rspec-controller-specs: the first expectation checks have_http_status, followed by a blank line.
Planner/StatusCheckedFirst:
  Enabled: true
  Include:
    - spec/controllers/**/*_spec.rb
    - spec/requests/**/*_spec.rb
```

### Shared shape of every cop file

```ruby
# frozen_string_literal: true

require 'rubocop'

module RuboCop
  module Cop
    module Planner
      # <one line: what it flags, naming the skill rule>
      class <Name> < Base
        ...
      end
    end
  end
end
```

- Subclass `RuboCop::Cop::Base`, not rubocop-rspec's base, so each file is self-contained.
- No `extend AutoCorrector`.
- Read lists with `cop_config.fetch('<Key>').map(&:to_sym)`.
- Shared terms used below:
  - **hook block**: a `block` node whose send node has a `nil` receiver and method `before`, `prepend_before`
    or `append_before` (so `config.before` in `spec_helper.rb` is not a hook block).
  - **example block**: a `block` node whose send node has a `nil` receiver and method `it`, `specify` or
    `example`.
  - **statements** of an example block: `[]` when the body is `nil`, `body.children` when the body is a
    `begin` node, otherwise `[body]`.
  - **request**: a `send` node with a `nil` receiver whose method is in `RequestMethods`.
  - **expectation statement**: a `send` node with method `to`, `not_to` or `to_not` whose receiver is
    `(send nil? :expect ...)`, `(block (send nil? :expect) ...)` or `(send nil? :is_expected)`.
  - **status check**: `(send (send nil? :expect (send nil? :response)) :to (send nil? :have_http_status _))`.
  - **missing blank line** after statement `a` followed by `b`: `b.first_line - a.last_line < 2`.

### `Planner/NoCompoundMatcher` (`cops/no_compound_matcher.rb`)

- `MSG = 'Write one `expect` per line instead of a compound matcher, and tag the example `:aggregate_failures`.'`
- `RESTRICT_ON_SEND = %i[to not_to to_not].freeze`
- Node matcher:

  ```ruby
  def_node_matcher :compound_matcher, <<~PATTERN
    (send {(send nil? :expect ...) (block (send nil? :expect) ...) (send nil? :is_expected)}
      {:to :not_to :to_not} $(send _ {:and :&} _) ...)
  PATTERN
  ```

- `on_send(node)`: `compound_matcher(node) { |matcher| add_offense(matcher) }`.

### `Planner/NoObjectsInBefore` (`cops/no_objects_in_before.rb`)

- `MSG = 'Create objects with `let!` or `let`, not in `before`.'`
- `on_block(node)`: return unless it is a hook block. For each `node.body&.each_node(:send)` (include the
  body itself), add an offence on the send node when either:
  - its receiver is `nil` and its method is in `CreationMethods`, or
  - its receiver is a `const` node and its method is in `ConstructorMethods`.
- Skip a send node that is one of the arguments, or inside one of the arguments, of a send with a `nil`
  receiver whose method is in `TimeTravelMethods` (so `travel_to Date.new(2024, 1, 1)` is not flagged). Sends
  in the block body of `travel_to(...) do ... end` are still checked.
- Nested blocks and stub arguments are not skipped (`and_return(build(:z))` is flagged).

### `Planner/NoRequestInBefore` (`cops/no_request_in_before.rb`)

- `MSG = 'Make the request in the example, not in `before`.'`
- `on_block(node)`: return unless it is a hook block. Add an offence on every request found in
  `node.body&.each_node(:send)`.

### `Planner/RequestFirst` (`cops/request_first.rb`)

- `MSG_FIRST = 'Make the request on the first line of the example.'`
- `MSG_BLANK_LINE = 'Follow the request with a blank line.'`
- `on_block(node)`: return unless it is an example block. With `statements`:
  1. Empty: add `MSG_FIRST` on `node.send_node`; return.
  2. `statements.first` is not a request: add `MSG_FIRST` on `statements.first`; return.
  3. A second statement exists and there is a missing blank line between the first and second: add
     `MSG_BLANK_LINE` on `statements.first`.

### `Planner/StatusCheckedFirst` (`cops/status_checked_first.rb`)

- `MSG_FIRST = 'Make the first expectation `expect(response).to have_http_status(...)`.'` (kept short so the
  line fits within this repo's 120-column `Layout/LineLength` limit)
- `MSG_BLANK_LINE = 'Follow the status check with a blank line.'`
- `on_block(node)`: return unless it is an example block. Find the index of the first expectation statement
  in `statements`.
  1. None: add `MSG_FIRST` on `node.send_node`; return.
  2. That statement is not a status check: add `MSG_FIRST` on it; return.
  3. A statement follows it and there is a missing blank line: add `MSG_BLANK_LINE` on the status check.

### Specs (`cops/spec/<cop_name>_spec.rb`)

Each spec file starts:

```ruby
# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'yaml'
require_relative '../<cop_name>'

RSpec.describe RuboCop::Cop::Planner::<Name>, :config do
  let(:cop_config) do
    YAML.load_file(File.expand_path('../../.rubocop.yml', __dir__))
        .fetch('Planner/<Name>')
        .except('Include')
  end
  ...
end
```

This keeps the specs on the same method lists as the config. Follow the `writing-rspec` skill. Keep each
example a short snippet using `expect_offense` / `expect_no_offenses`. Cover:

- **NoCompoundMatcher**: flags `.and`; flags `&`; flags `.and` after `not_to`; flags `.and` with
  `is_expected`; flags `.and` with a block `expect { ... }.to change { ... }.and change { ... }`; does not
  flag `.or` or `|`; does not flag two separate `expect` lines; does not flag `allow(x).to receive(:y).and_return(1)`.
- **NoObjectsInBefore**: flags `create`, `build_stubbed` and `double` in `before`; flags `Widget.new`,
  `Widgets::Widget.create` and `FactoryBot.create`; flags them in `prepend_before` and `append_before`;
  flags `build` inside `and_return(...)`; does not flag stubs or `sign_in user`; does not flag
  `travel_to Time.new(2024, 1, 1)` or `travel_to Date.new(2024, 1, 1)`; flags `create` inside the block of
  `travel_to(...) do ... end`; does not flag `create` in `let!`, `after` or `around`; does not flag
  `config.before { create(:x) }`.
- **NoRequestInBefore**: flags `get :index` and `post "/widgets"` in `before`; does not flag
  `request.headers[...] = ...` or `sign_in user` in `before`; does not flag `get :index` inside `it`.
- **RequestFirst**: no offence for request, blank line, expectation; no offence for an example that is only
  the request; flags an expectation before the request; flags a missing blank line after the request;
  flags an empty example; flags `it { is_expected.to ... }`; applies to `specify` and `example`.
- **StatusCheckedFirst**: no offence for request, status check, blank line, other expectations; no offence
  when the status check is the last statement; no offence when a non-expectation line comes before the
  status check; flags a first expectation that is not the status check; flags a missing blank line after
  the status check; flags an example with no expectations.

## Verification

Run from the repo root.

1. `bundle exec rspec docs/plans/202611050909-convert-skills-to-rubocop-config/cops/spec` passes.
2. `bundle exec rubocop -c .rubocop.yml docs/plans/202611050909-convert-skills-to-rubocop-config/cops/*.rb`
   reports no offences. `-c` is required so RuboCop does not pick up the folder's own `.rubocop.yml`, and the
   files must be named individually because directories under `docs/**` are excluded. Do not lint
   `cops/spec`.
3. Smoke-test the config loads and the cops fire, without writing files:

   ```sh
   printf 'RSpec.describe WidgetsController do\n  before do\n    get :index\n    create(:widget)\n  end\n\n  it "shows widgets" do\n    expect(described_class).to eq(1).and eq(2)\n  end\nend\n' | bundle exec rubocop -c docs/plans/202611050909-convert-skills-to-rubocop-config/.rubocop.yml --only Planner/NoCompoundMatcher,Planner/NoObjectsInBefore,Planner/NoRequestInBefore,Planner/RequestFirst,Planner/StatusCheckedFirst,RSpec/DescribedClass --stdin docs/plans/202611050909-convert-skills-to-rubocop-config/spec/controllers/widgets_controller_spec.rb
   ```

   It reports one offence each for `Planner/NoCompoundMatcher`, `Planner/NoObjectsInBefore`,
   `Planner/NoRequestInBefore`, `Planner/RequestFirst`, `Planner/StatusCheckedFirst` and
   `RSpec/DescribedClass`.
4. `bundle exec rake` (specs, then RuboCop) passes.

Do not add `rake install` or any step that writes outside the repo.

## Commit

Commit only after the change has been implemented and every Verification step passes. Never commit before.

Stage exactly, under `docs/plans/202611050909-convert-skills-to-rubocop-config/`:

- `.rubocop.yml`
- `cops/` (the five cop files and `cops/spec/`)
- `ITERATION-002.md`
- `PLAN-002.md`
- `REVIEW-002.md`

Suggested commit message (write it with the `commit-message` skill, which sets the trailer):

```
Add a RuboCop config for the RSpec skill rules

FINDINGS-001 found which writing-rspec and
writing-rspec-controller-specs rules RuboCop can check. This adds a
config in the plan folder that enables the matching rubocop-rspec cops
and five custom Planner cops for compound matchers, objects created in
before, and the shape of controller and request examples.

The config is meant to be copied into an app's RuboCop config. It is
not shipped with the gem, and the skills are unchanged.
```

## Deviations

- `Metrics/AbcSize` failed on `StatusCheckedFirst#on_block` because the method was too long; changed
  `cops/status_checked_first.rb` to move steps 2 and 3 into a private `check_status` method.
- The `RequestFirst` spec for `it { is_expected.to be_ok }` failed because its caret line was one character
  too long; changed `cops/spec/request_first_spec.rb` to use the correct caret count.

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-12T16:55:02Z |
| Finished | 2026-11-12T16:56:16Z |
| Elapsed | 1m 14s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sed -i 's/.../.../' .../request_first_spec.rb` | Failed with a sed syntax error on macOS, so I redid the change with the Edit tool | Use Edit instead of `sed -i` on macOS |
