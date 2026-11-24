# PLAN-001 — Add `planner next` to create the next iteration file

Add a `planner next <plan-folder>` command that creates the next zero-padded, empty `ITERATION-<NNN>.md`
in a plan folder and prints its path. The number is one more than the highest `ITERATION-NNN.md` already
in the folder, or `001` when there is none. The file stays empty for now (no brief template). Specs, the
CLI usage text, the README, the glossary and `docs/TODO.md` are updated to match.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Argument | `planner next <plan-folder>`: exactly one required argument, a plan folder only (no file) |
| Extra or missing arguments, unknown options | `UsageError` (prints usage, exit 1), like `planner toc` |
| Missing path or not a directory | `Error`: `<folder> is not a directory` (same as `planner toc`), exit 1 |
| Numbering | Highest number among `ITERATION-NNN.md` files only, plus one; other kinds (FINDINGS, PLAN, REVIEW …) are ignored |
| Which names count | Only exactly `ITERATION-` + three digits + `.md`; unpadded names (`ITERATION-15.md`) and lettered names (`ITERATION-002-a.md`) are ignored |
| No ITERATION file in the folder | Create `ITERATION-001.md` |
| Guard on the latest iteration (empty, unplanned) | None: always create the next file |
| Past 999 | No special handling and no spec |
| File content | Zero bytes, as `planner new` writes |
| Output | The new file's path: the folder as typed with any trailing `/` dropped, joined with the file name, e.g. `docs/plans/202611241536-x/ITERATION-002.md` |
| TABLE-OF-CONTENT.md | Not touched by `next` |
| Docs | README (new `planner next` section and the intro), GLOSSARY "iteration file" entry, `Planner::CLI::USAGE` |
| TODO | Remove the Advised TODO item about `planner next` from `docs/TODO.md` |
| Specs | New `spec/planner/commands/next_spec.rb`; one example in `spec/exe/planner_spec.rb` running `new` then `next`; a dispatch example in `spec/planner/cli_spec.rb` |
| Commit | Yes |

## Files to create / change

- `lib/planner/commands/next.rb` (new): `Planner::Commands::Next`.
- `lib/planner.rb`: require it.
- `lib/planner/cli.rb`: register `next`, add it to `USAGE`.
- `spec/planner/commands/next_spec.rb` (new).
- `spec/planner/cli_spec.rb`: one new example.
- `spec/exe/planner_spec.rb`: one new example.
- `README.md`: intro sentence and a new `### planner next` section.
- `docs/GLOSSARY.md`: "iteration file" entry.
- `docs/TODO.md`: remove one line.

## Implementation

### `lib/planner/commands/next.rb`

```ruby
# frozen_string_literal: true

module Planner
  module Commands
    # Creates the next empty ITERATION-<NNN>.md in a plan folder, numbered one past the highest
    # ITERATION-NNN.md there, and prints the file's path.
    class Next
      ITERATION = /\AITERATION-(\d{3})\.md\z/

      def initialize(context)
        @context = context
      end

      def call(args)
        raise UsageError if args.size != 1 || args.first.start_with?('-')

        folder = args.first.chomp('/')
        raise Error, "#{folder} is not a directory" unless File.directory?(folder)

        path = File.join(folder, format('ITERATION-%03d.md', next_number(folder)))
        File.write(path, '')
        @context.stdout.puts path
      end

      private

      def next_number(folder)
        names = Dir.children(folder).select { |name| File.file?(File.join(folder, name)) }
        numbers = names.filter_map { |name| name[ITERATION, 1]&.to_i }
        (numbers.max || 0) + 1
      end
    end
  end
end
```

Notes for the implementer:

- The folder is resolved like `planner toc` does it: as given, relative to the current directory.
- Only regular files count, so a directory with a matching name is ignored.
- Rejecting an argument that starts with `-` makes any option (e.g. `--dir`) a `UsageError`, since `next` has
  no options.
- Keep within RuboCop's limits; split methods if `Metrics/*` complains.

### `lib/planner.rb`

Add `require_relative 'planner/commands/next'` after `require_relative 'planner/commands/new'`.

### `lib/planner/cli.rb`

- Add `'next' => Commands::Next,` to `COMMANDS` after `'new'`.
- Add `       planner next <plan-folder>` to `USAGE` on the line after the `planner new` line, aligned with the
  other lines.

### `spec/planner/commands/next_spec.rb`

Follow the `writing-rspec` skill and the setup of `spec/planner/commands/toc_spec.rb` (context with
`root: Pathname.pwd`, a `StringIO` stdout, `let(:folder) { 'docs/plans/x' }`, `FileUtils.mkdir_p(folder)` in
`before`). Examples:

- creates an empty `ITERATION-001.md` and prints `"docs/plans/x/ITERATION-001.md\n"` in a folder with no files.
- creates `ITERATION-003.md` (zero bytes) when `ITERATION-001.md` and `ITERATION-002.md` exist, and prints its path.
- uses the highest number, not the count: with only `ITERATION-001.md` and `ITERATION-005.md`, creates
  `ITERATION-006.md`.
- ignores other kinds: with `ITERATION-001.md`, `PLAN-001.md`, `FINDINGS-004.md` and `REVIEW-003.md`, creates
  `ITERATION-002.md`.
- ignores unpadded and lettered names: with `ITERATION-001.md`, `ITERATION-15.md` and `ITERATION-002-a.md`,
  creates `ITERATION-002.md`.
- creates the file even when the latest iteration is empty (`ITERATION-001.md` of zero bytes → `ITERATION-002.md`).
- drops a trailing slash: `command.call(['docs/plans/x/'])` prints `"docs/plans/x/ITERATION-001.md\n"`.
- leaves existing files unchanged (write content into `ITERATION-001.md` first, check it is unchanged).
- raises `Planner::Error, 'nope is not a directory'` for a missing path.
- raises `Planner::Error, '<file> is not a directory'` when given a file (e.g. `docs/plans/x/ITERATION-001.md`).
- raises `Planner::UsageError` with no args, with two args, and with an option (e.g. `['--dir', folder]`).

### `spec/planner/cli_spec.rb`

Add after `'dispatches toc'`:

```ruby
it 'dispatches next' do
  expect(cli.call(%w[next nope])).to eq(1)
  expect(stderr.string).to eq("[planner] nope is not a directory\n")
end
```

### `spec/exe/planner_spec.rb`

Add after the `new` example:

- `'creates the next iteration file with next'`: run `planner('new', 'Next Test')`, then
  `planner('next', File.dirname(out.chomp))`. Expect exit status 0, stdout to match
  `%r{\Adocs/plans/\d{12}-next-test/ITERATION-002\.md\n\z}`, and `File.file?` of that path to be true.

### `README.md`

Use the `update-readme` skill.

- Intro sentence: after "…and write the task's brief in it." add
  `` For each later iteration, `planner next <plan-folder>` creates the next empty `ITERATION-<NNN>.md`.``
- Add a section after `### planner new`:

  ````markdown
  ### planner next

  ```sh
  planner next <plan-folder>
  ```

  Creates the next empty `ITERATION-<NNN>.md` in a plan folder, numbered one past the highest `ITERATION-NNN.md` there (or `001` when there is none), and prints the file's path.

  ```sh
  planner next docs/plans/202610271216-add-login  # => docs/plans/202610271216-add-login/ITERATION-002.md
  ```
  ````

### `docs/GLOSSARY.md`

Change the "iteration file" entry to:
`` - **iteration file**: `ITERATION-<NNN>.md`. The brief for one iteration of work. The first is created by `planner new`, and each later one by `planner next`.``

### `docs/TODO.md`

Delete the line beginning `` - Add a `planner next <plan-folder>` command that creates the next zero-padded `` under
"Advised TODO.". Leave every other line as it is, including the uncommitted edits already in the file.

## Verification

1. `bundle exec rspec spec/planner/commands/next_spec.rb spec/planner/cli_spec.rb spec/exe/planner_spec.rb` passes.
2. `bundle exec rake` (specs, then RuboCop) passes with no offences.

Do not add `rake install` or any step that writes outside the repo.

## Commit

Commit only after the change has been implemented and every Verification step passes. Never commit before.

Stage exactly:

- `lib/planner/commands/next.rb`
- `lib/planner.rb`
- `lib/planner/cli.rb`
- `spec/planner/commands/next_spec.rb`
- `spec/planner/cli_spec.rb`
- `spec/exe/planner_spec.rb`
- `README.md`
- `docs/GLOSSARY.md`
- `docs/TODO.md`
- `docs/plans/202611241536-next-command/` (`ITERATION-001.md` and `PLAN-001.md`)

Suggested commit message (write it with the `commit-message` skill):

```
Add planner next to create the next iteration file

Iteration files after the first were made by hand, which led to
unpadded names such as ITERATION-15.md. planner next <plan-folder>
creates the next empty, zero-padded ITERATION-<NNN>.md, numbered one
past the highest ITERATION-NNN.md in the folder, and prints its path.

The README, glossary, usage text and todo list are updated to match.

Assisted-by: Claude Code (Claude Opus 5.5, plan)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-24T15:53:28Z |
| Finished | 2026-11-24T15:54:00Z |
| Elapsed | 32s |
| Model | sonnet |
| Tokens | ~60k (estimate) |
