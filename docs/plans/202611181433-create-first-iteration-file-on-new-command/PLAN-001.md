# PLAN-001 — Create an empty `ITERATION-001.md` with `planner new`

`planner new` creates the plan folder as today and also creates an empty (zero-byte) `ITERATION-001.md`
inside it. It now prints the path of that file instead of the folder's. Specs, the README, the glossary
and the class comment are updated to match, and the matching item is removed from `docs/TODO.md`.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| File content | Zero bytes (no newline) |
| Printed output | The file path only: `<folder as today>/ITERATION-001.md` (e.g. `docs/plans/202610271216-hello/ITERATION-001.md`); with `--dir` it follows the dir as typed, absolute stays absolute |
| New tests | In `spec/planner/commands/new_spec.rb` |
| Exe spec | Update the existing `new` example in `spec/exe/planner_spec.rb` to expect the file path and check the file exists; no other new examples there |
| Docs | README `planner new` entry, GLOSSARY "plan folder" entry, class comment on `Planner::Commands::New` |
| README examples | Update both `# =>` comments to show the file path |
| TODO | Remove the `planner new` should also create `ITERATION-001.md` item from `docs/TODO.md` |
| Commit | Yes |

## Files to create / change

- `lib/planner/commands/new.rb`: create the file, print its path, class comment.
- `spec/planner/commands/new_spec.rb`: expect the file path on stdout; new examples for the file.
- `spec/exe/planner_spec.rb`: update the `new` example.
- `README.md`: `new` entry and the two examples.
- `docs/GLOSSARY.md`: "plan folder" entry.
- `docs/TODO.md`: remove one line.

## Implementation

### `lib/planner/commands/new.rb`

- Add `ITERATION_FILE = 'ITERATION-001.md'` below `DEFAULT_DIR`.
- Change the class comment to:
  `# Creates a plan folder under docs/plans, or the folder given with --dir, with an empty ITERATION-001.md, and prints the file's path.`
  (wrap onto a second `#` line if RuboCop's line length requires it).
- In `call`, replace the last two lines

  ```ruby
  FileUtils.mkdir_p(path)
  @context.stdout.puts folder
  ```

  with

  ```ruby
  FileUtils.mkdir_p(path)
  (path / ITERATION_FILE).write('')
  @context.stdout.puts folder / ITERATION_FILE
  ```

  Everything else (option parsing, name and slug checks, the "already exists" error naming the folder)
  stays as is.

### `spec/planner/commands/new_spec.rb`

Follow the `writing-rspec` skill.

- Update every stdout expectation to end in `/ITERATION-001.md\n` instead of `\n` after the folder, e.g.
  `"docs/plans/202610271216-hello-world/ITERATION-001.md\n"`, `"work/plans/202610271216-hello/ITERATION-001.md\n"`,
  `"#{elsewhere}/202610271216-hello/ITERATION-001.md\n"`, `"../outside/202610271216-hello/ITERATION-001.md\n"`.
  Keep the existing `be_directory` checks.
- Rename `'creates the plan folder and prints its relative path'` to
  `'creates the plan folder and prints the relative path of its ITERATION-001.md'`.
- Add:
  - `'creates an empty ITERATION-001.md in the plan folder'`: `command.call(['Hello'])`, then expect
    `root.join('docs/plans/202610271216-hello/ITERATION-001.md')` to be a file and its `size` to eq `0`.
  - `'creates an empty ITERATION-001.md in the --dir folder'`: `command.call(['--dir', 'work', 'Hello'])`,
    then the same checks on `root.join('work/202610271216-hello/ITERATION-001.md')`.

The error examples are unchanged.

### `spec/exe/planner_spec.rb`

In `'creates a plan folder with new'`:

- Rename to `'creates a plan folder with an ITERATION-001.md with new'`.
- Expect `out` to match `%r{\Adocs/plans/\d{12}-hello-world/ITERATION-001\.md\n\z}`.
- Replace the directory check with `expect(File.file?(out.chomp)).to be(true)`.

### `README.md`

Use the `update-readme` skill.

- Change the `new` entry to:
  `` - `planner new [--dir <folder>] <given-name>`: create a plan folder under `docs/plans/`, or under `--dir` (`-d`) relative to the project root, with an empty `ITERATION-001.md` in it, and print the path of that file.``
- Change the examples to:

  ```sh
  planner new "Add login"  # => docs/plans/202610271216-add-login/ITERATION-001.md
  planner new --dir work/plans "Add login"  # => work/plans/202610271216-add-login/ITERATION-001.md
  ```

### `docs/GLOSSARY.md`

Change the "plan folder" entry's last sentence from `Created by \`planner new\`.` to
`` Created by `planner new`, with an empty `ITERATION-001.md` in it.``

### `docs/TODO.md`

Delete the line `` - `planner new` should also create `ITERATION-001.md` in the new plan folder.`` Leave every
other line as it is.

## Verification

1. `bundle exec rspec spec/planner/commands/new_spec.rb spec/exe/planner_spec.rb spec/planner/cli_spec.rb`
   passes.
2. `bundle exec rake` (specs, then RuboCop) passes with no offences.

Do not add `rake install` or any step that writes outside the repo.

## Commit

Commit only after the change has been implemented and every Verification step passes. Never commit before.

Stage exactly:

- `lib/planner/commands/new.rb`
- `spec/planner/commands/new_spec.rb`
- `spec/exe/planner_spec.rb`
- `README.md`
- `docs/GLOSSARY.md`
- `docs/TODO.md`
- `docs/plans/202611181433-create-first-iteration-file-on-new-command/` (`ITERATION-001.md` and `PLAN-001.md`)

Suggested commit message (write it with the `commit-message` skill, which sets the trailer):

```
Create an empty ITERATION-001.md with planner new

planner new only created the plan folder, so the first brief had to be
created by hand. It now also creates an empty ITERATION-001.md in the
folder and prints that file's path, ready to open in an editor.

The README, glossary and todo list are updated to match.
```

## Deviations

- `spec/planner/cli_spec.rb` 'returns 0 on success' failed because `planner new` now prints the `ITERATION-001.md` path; changed `spec/planner/cli_spec.rb` to expect `docs/plans/202610271216-hello/ITERATION-001.md\n`
- RuboCop `Metrics/AbcSize` failed on `Planner::Commands::New#call` because of the added line; changed `lib/planner/commands/new.rb` to move the folder and file creation into a private `create` method

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-18T14:44:40Z |
| Finished | 2026-11-18T14:45:30Z |
| Elapsed | 50s |
| Model | sonnet |
| Tokens | ~40k (estimate) |
