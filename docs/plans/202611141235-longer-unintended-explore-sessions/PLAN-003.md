# PLAN-003 — Split the explore prompt into partials

Move the Findings structure, Check-in, Stats and Summary for the user sections of
`lib/planner/prompts/explore.md.erb` into four partials, so the deep explore prompt in PLAN-004 can share
them. This is a refactor with no change to the rendered prompt. Part of PLAN-002 (step 1), from
FINDINGS-001 finding 12 item 1.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Partials | `_explore_findings_structure.md.erb`, `_explore_check_in.md.erb`, `_explore_stats.md.erb`, `_explore_summary_for_user.md.erb` in `lib/planner/prompts/` |
| Section headings | Stay in `explore.md.erb`. Each partial holds only the section's body |
| How partials render | `Commands::Explore#prompt` renders each one with ERB and passes the result, without its trailing newline, as a template local, like `table_of_content` |
| Check | The existing specs only, unchanged |
| Commit | Yes |

## Files to create / change

- `lib/planner/prompts/_explore_findings_structure.md.erb` (new)
- `lib/planner/prompts/_explore_check_in.md.erb` (new)
- `lib/planner/prompts/_explore_stats.md.erb` (new)
- `lib/planner/prompts/_explore_summary_for_user.md.erb` (new)
- `lib/planner/prompts/explore.md.erb`
- `lib/planner/commands/explore.rb`

## Implementation

### The partials

In `lib/planner/prompts/explore.md.erb`, each section below runs from the line after its heading's blank
line to the line before the blank line that comes before the next heading. Move each one, unchanged, into
its partial, ending the partial with a single newline:

| Section heading | Partial |
| --- | --- |
| `## Findings structure` | `_explore_findings_structure.md.erb` (from the ```` ```markdown ```` line to `model.`) |
| `## Check-in` | `_explore_check_in.md.erb` (from `After each round's write, reply here in exactly this` to `when there are none.`) |
| `## Stats` | `_explore_stats.md.erb` (from `As you go, keep a list of every command you could not` to `table when there were none.`) |
| `## Summary for the user` | `_explore_summary_for_user.md.erb` (from `When the user tells you to finish and the final file` to the end of the file) |

### `lib/planner/prompts/explore.md.erb`

Put a local in place of each moved body, so the end of the file reads:

````
## Findings structure

<%= findings_structure %>

## Check-in

<%= check_in %>

## Stats

<%= stats %>

## Table of contents

<%= table_of_content %>

## Summary for the user

<%= summary_for_user %>
````

The file ends with a single newline after `<%= summary_for_user %>`. Everything above
`## Findings structure` stays as it is.

### `lib/planner/commands/explore.rb`

Add below `ITERATION_NAME`:

```ruby
PARTIALS = %w[findings_structure check_in stats summary_for_user].freeze
```

Replace `prompt` with:

```ruby
def prompt(file, findings_file, model)
  folder = File.dirname(file)
  locals = { findings_file:, model:, title: File.basename(findings_file, '.md') }
  ERB.new(File.read(TEMPLATE)).result_with_hash(
    iteration_file: file, folder:, toc_file: TableOfContent.path(folder),
    table_of_content: TableOfContent.section(folder, update: true), **locals, **partials(locals)
  )
end

# Each _explore_<name>.md.erb partial rendered with locals, without its trailing newline, keyed by name.
def partials(locals)
  PARTIALS.to_h do |name|
    path = File.expand_path("../prompts/_explore_#{name}.md.erb", __dir__)
    [name.to_sym, ERB.new(File.read(path)).result_with_hash(locals).chomp]
  end
end
```

## Verification

1. `bundle exec rake` passes, with `spec/planner/commands/explore_spec.rb` unchanged.

## Commit

Commit only after the change is made and Verification passes. Stage:

- `lib/planner/prompts/_explore_findings_structure.md.erb`
- `lib/planner/prompts/_explore_check_in.md.erb`
- `lib/planner/prompts/_explore_stats.md.erb`
- `lib/planner/prompts/_explore_summary_for_user.md.erb`
- `lib/planner/prompts/explore.md.erb`
- `lib/planner/commands/explore.rb`
- `docs/plans/202611141235-longer-unintended-explore-sessions/PLAN-003.md`

Suggested commit message:

```
Split the explore prompt's shared sections into partials

The findings structure, check-in, stats and summary sections move into
_explore_*.md.erb partials, so a deep explore prompt can share them.
The rendered prompt does not change.
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-14T16:48:11Z |
| Finished | 2026-11-14T16:48:25Z |
| Elapsed | 14s |
| Model | sonnet |
| Tokens | ~25k (estimate) |
