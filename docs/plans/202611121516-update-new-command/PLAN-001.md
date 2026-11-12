# PLAN-001 — Add a `--dir` option to `planner new`

Add `planner new [--dir <folder>] <given-name>`. `--dir` (`-d`) names the folder the plan folder is
created in, replacing `docs/plans`, which stays the default. The printed path follows the folder as the
user typed it. The `plan` prompt stops hard-coding `docs/plans/` and names the parent folder of the plan
folder instead, so plans kept elsewhere still point the agent at their sibling plans.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| What the option replaces | The whole `docs/plans` part: `--dir work/plans` creates `work/plans/<stamp>-<slug>` |
| Default | `docs/plans`, unchanged |
| Option name | `--dir` / `-d` |
| Path resolution | Relative paths resolve against the project root (`@context.root`); absolute paths and paths outside the project are accepted as given |
| Folder does not exist | Create it and any missing parents (`FileUtils.mkdir_p`, as today) |
| Printed path | As the user typed it: `<dir as given>/<stamp>-<slug>`; absolute stays absolute, relative stays relative. With no `--dir` it prints `docs/plans/<stamp>-<slug>` as today |
| Empty (`--dir ""`) or missing value | `UsageError` (usage text, exit 1) |
| `plan` prompt's "elsewhere in `docs/plans/`" | Replace with the parent folder of the plan folder, rendered from the iteration file's path |
| Commit | Yes |

## Files to create / change

- `lib/planner/commands/new.rb`: parse `--dir`, build and print the path from it.
- `spec/planner/commands/new_spec.rb`: specs for `--dir`.
- `lib/planner/cli.rb`: usage line.
- `lib/planner/commands/plan.rb`: pass `plans_dir` to the template.
- `lib/planner/prompts/plan.md.erb`: use `plans_dir`.
- `spec/planner/commands/plan_spec.rb`: spec for the rendered parent folder.
- `README.md`: usage entry and example.

## Implementation

### `lib/planner/commands/new.rb`

- Add `DEFAULT_DIR = 'docs/plans'`.
- Update the class comment to: `# Creates a plan folder under docs/plans, or the folder given with --dir, and prints its path.`
- `call(args)`:
  1. `dir = parse(args)` (removes options from `args`, like `Summarise#parse`).
  2. `raise UsageError if dir.empty?` (covers `--dir ""`).
  3. Keep the existing name check (`args.first`, `UsageError` when nil or empty; extra args still ignored).
  4. `folder = Pathname(dir) / "#{stamp}-#{slug}"` — the path as typed, built in a private method that
     keeps the existing slug check and `Error` message (`'<name>' does not contain any usable characters`).
  5. `path = @context.root / folder` (an absolute `folder` stays absolute under `Pathname#/`).
  6. `raise Error, "#{path} already exists" if path.directory?` (same message as today).
  7. `FileUtils.mkdir_p(path)`, then `@context.stdout.puts folder`.
- `parse(args)`:

  ```ruby
  # Removes the options from args and returns the chosen folder.
  def parse(args)
    dir = DEFAULT_DIR
    OptionParser.new do |opts|
      opts.on('-d', '--dir DIR') { |value| dir = value }
    end.parse!(args)
    dir
  rescue OptionParser::ParseError
    raise UsageError
  end
  ```

  A missing value (`--dir` as the last arg) raises `OptionParser::MissingArgument` → `UsageError`.
- `relative_path_from` is no longer used.

### `spec/planner/commands/new_spec.rb`

Keep the existing examples (they must still pass unchanged). Add:

- `--dir work/plans Hello` creates `root/work/plans/202610271216-hello` and prints `work/plans/202610271216-hello\n`.
- `-d work Hello` prints `work/202610271216-hello\n`.
- The option after the name (`Hello --dir work`) works the same.
For the next two examples set `root` to `Pathname.pwd / 'project'` (created first), so every folder
stays inside the spec's tmp dir:

- An absolute `--dir` (`(Pathname.pwd / 'elsewhere').to_s`) creates `<pwd>/elsewhere/202610271216-hello`
  and prints that absolute path.
- A relative `--dir` outside the root (`../outside`) creates `<pwd>/outside/202610271216-hello` and
  prints `../outside/202610271216-hello\n`.
- `--dir ""` raises `Planner::UsageError`.
- `--dir` with no value (`['Hello', '--dir']`) raises `Planner::UsageError`.
- An unknown option (`['--nope', 'Hello']`) raises `Planner::UsageError`.
- The "already exists" error with `--dir work` names `#{root}/work/202610271216-hello`.

Follow the `writing-rspec` skill.

### `lib/planner/cli.rb`

Change the usage line to `usage: planner new [--dir <folder>] <given-name>` (keep the alignment of the
other lines).

### `lib/planner/commands/plan.rb` and `lib/planner/prompts/plan.md.erb`

- In `Plan#prompt`, pass `plans_dir: File.dirname(folder)` to `result_with_hash`.
- In the template, change
  ``Match the convention already used by `PLAN-*.md` files elsewhere in `docs/plans/`:``
  to
  ``Match the convention already used by `PLAN-*.md` files elsewhere in `<%= plans_dir %>/`:``
- Add to `plan_spec.rb` an example: for `docs/plans/x/ITERATION-001.md` the prompt includes
  ``elsewhere in `docs/plans/`:``; and one with an iteration at `work/x/ITERATION-001.md` whose prompt
  includes ``elsewhere in `work/`:``.

### `README.md`

Use the `update-readme` skill. Change the `new` entry to:
`` `planner new [--dir <folder>] <given-name>`: create a plan folder under `docs/plans/`, or under `--dir` (`-d`) relative to the project root, and print its path.``
Add a second example line below the existing one:
`planner new --dir work/plans "Add login"  # => work/plans/202610271216-add-login`

## Verification

1. `bundle exec rspec spec/planner/commands/new_spec.rb spec/planner/commands/plan_spec.rb spec/planner/cli_spec.rb spec/exe/planner_spec.rb`
2. `bundle exec rake` (specs, then RuboCop) passes with no offences.
3. From the repo root: `bundle exec exe/planner new --dir "$TMPDIR/planner-check" "Dir check"` prints
   `$TMPDIR/planner-check/<stamp>-dir-check` (absolute, as typed) and the folder exists. Remove it afterwards.
4. `bundle exec exe/planner new --dir "" x` and `bundle exec exe/planner new x --dir` each print the usage
   text (first line `usage: planner new [--dir <folder>] <given-name>`) and exit 1.

Do not add `rake install` or any step that writes outside the repo other than `$TMPDIR` in step 3.

## Commit

Commit only after the change has been implemented and every Verification step passes. Never commit before.

Stage exactly:

- `lib/planner/commands/new.rb`
- `spec/planner/commands/new_spec.rb`
- `lib/planner/cli.rb`
- `lib/planner/commands/plan.rb`
- `lib/planner/prompts/plan.md.erb`
- `spec/planner/commands/plan_spec.rb`
- `README.md`
- `docs/plans/202611121516-update-new-command/` (`ITERATION-001.md` and `PLAN-001.md`)

Suggested commit message (write it with the `commit-message` skill, which sets the trailer):

```
Add a --dir option to planner new

planner new always created plan folders under docs/plans. --dir (-d)
now names a different folder, relative to the project root or
absolute, and the printed path follows it as typed. docs/plans stays
the default.

The plan prompt now points at the plan folder's parent instead of a
hard-coded docs/plans/, so plans kept elsewhere still find their
siblings.
```

## Deviations

- RuboCop failed (Layout/LineLength) because the `plans_dir:` hash entry made a line in `plan.rb` 124 characters; changed
  `lib/planner/commands/plan.rb` to move `toc_file:` onto its own line

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-12T15:29:30Z |
| Finished | 2026-11-12T15:30:22Z |
| Elapsed | 52s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sed -i 's#...#...#' lib/planner/prompts/plan.md.erb` | BSD sed rejected the in-place flag form; redone with Edit | Use the Edit tool for in-place changes |
| `bundle exec exe/planner new --dir "$TMPDIR/planner-check" "Dir check"; ls ...; rm -rf ...` | Denied as a compound command; rerun as separate calls | Run each command in its own call |
