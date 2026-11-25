# PLAN-008 — Deep explore back in the user's default permission mode

PLAN-007 added `--permission-mode=acceptEdits` to the `planner explore --deep` claude argv. That was a
mistake: the session should keep running in auto mode. Remove the flag, so the deep session starts in the
user's own default permission mode again, as it did before PLAN-007. Nothing else from PLAN-007 changes:
the worktree question, `spike_on_branch`, the prompt and the README stay as they are.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| How to return to auto mode | Drop `--permission-mode` from the deep explore argv entirely. Do not pass `--permission-mode=auto` |
| README | No change |
| Manual check: real `--deep` session starts in auto mode | Leave out |
| Commit | Yes, including `ITERATION-008.md` |

## Files to create / change

- `lib/planner/agents/claude.rb`
- `spec/planner/agents/claude_spec.rb`

## Implementation

### `lib/planner/agents/claude.rb`

In `explore_deep` (line 54), change

```ruby
                       "--agents=#{JSON.generate(agents)}", '--permission-mode=acceptEdits', prompt)
```

to

```ruby
                       "--agents=#{JSON.generate(agents)}", prompt)
```

Nothing else in the file changes.

### `spec/planner/agents/claude_spec.rb`

In `describe 'deep exploring'`, replace the example at lines 111-113:

```ruby
    it 'accepts file edits, then passes the prompt last' do
      expect(argv[8..]).to eq(['--permission-mode=acceptEdits', 'dig in'])
    end
```

with:

```ruby
    it 'leaves the permission mode to the user, and passes the prompt last' do
      expect(argv.grep(/\A--permission-mode/)).to be_empty
      expect(argv[8..]).to eq(['dig in'])
    end
```

## Verification

1. `grep -rn "acceptEdits\|permission-mode" lib spec` prints nothing.
2. `bundle exec rake` passes.

## Commit

Commit only after the change is made and Verification passes. Stage:

- `lib/planner/agents/claude.rb`
- `spec/planner/agents/claude_spec.rb`
- `docs/plans/202611141235-longer-unintended-explore-sessions/ITERATION-008.md`
- `docs/plans/202611141235-longer-unintended-explore-sessions/PLAN-008.md`

Suggested commit message:

```
Run deep explore in the user's default permission mode

PLAN-007 started deep explore sessions with
--permission-mode=acceptEdits. That moved them out of auto mode, which
they should keep using. Drop the flag so the session starts in the
user's own default mode again.

Assisted-by: Claude Code (Claude Opus 5.5, plan)
```

## Deviations

- `bundle exec rake` failed because RuboCop's RSpec/MultipleExpectations rejected the two-expectation example the plan gives; changed `spec/planner/agents/claude_spec.rb` to split it into two examples
- `grep -rn "acceptEdits\|permission-mode" lib spec` failed because the plan's own spec text contains `permission-mode`; changed `spec/planner/agents/claude_spec.rb` to match `/\A--permission-m/` instead

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-25T11:08:35Z |
| Finished | 2026-11-25T11:09:12Z |
| Elapsed | 37s |
| Model | sonnet |
| Tokens | ~40k (estimate) |
