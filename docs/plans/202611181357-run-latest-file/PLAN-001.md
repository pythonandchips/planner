# PLAN-001 — Let commands take a plan folder and pick its latest file

Let `planner plan`, `explore`, `review`, `run` and `summarise` take a plan folder in place of a
file. Given a folder, each command picks the highest-numbered file of the kinds it accepts and
then carries on exactly as if that file had been given. If the folder has no such file, or two
kinds share the highest number, the command fails with an error. `planner run <file>` also
starts checking that it was given a `PLAN-<N>.md` file. In scope: a shared `LatestFile`
module, the five commands, CLI usage text, specs, README, GLOSSARY and `docs/TODO.md`.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Commands that take a folder | `plan`, `explore`, `review`, `run`, `summarise` |
| Kinds each command picks from | `plan` and `explore`: `ITERATION`. `run`: `PLAN`. `review`: `PLAN` or `FINDINGS`. `summarise`: `PLAN`, `FINDINGS` or `REVIEW` |
| "Highest" | Highest number among the files of the command's kinds, ignoring every other file. E.g. `run` on a folder with `PLAN-002.md` and `ITERATION-003.md` uses `PLAN-002.md` |
| Lettered files | Within one kind and number, the last letter wins: base, then `-a`, `-b` … `-z`, `-aa` … (`FINDINGS-002-b.md` beats `FINDINGS-002-a.md` and `FINDINGS-002.md`) |
| Two kinds share the highest number | Error, for every pair of kinds (including `PLAN-003.md` with `REVIEW-003.md` for `summarise`) |
| No suitable file | Error listing the kinds, in the wording of the existing "is not a" errors |
| No-file error | `<folder> has no ITERATION-<N>.md file`, `<folder> has no PLAN-<N>.md file`, `<folder> has no PLAN-<N>.md or FINDINGS-<N>.md file`, `<folder> has no PLAN-<N>.md, REVIEW-<N>.md or FINDINGS-<N>.md file` |
| Tie error | `<folder> has more than one latest file: <file>, <file>; give the file instead`, naming the latest file of each tied kind, alphabetically |
| Announce the chosen file | No |
| `run <file>` name check | Added: `<file> is not a PLAN-<N>.md file`, checked before `<file> does not exist` |
| Docs | CLI usage text, README bullets, a GLOSSARY entry |
| README merge-conflict leftovers | Already fixed by the user in the working tree. Add a global todo for a full README content update |
| Existing todos | Remove the two items this change completes, per the `writing-todos` skill |
| Commit | Yes |

## Files to create / change

```
lib/planner/latest_file.rb                 new: picks the latest file in a folder
lib/planner.rb                             require it before the commands
lib/planner/commands/plan.rb               resolve a folder argument
lib/planner/commands/explore.rb            resolve a folder argument
lib/planner/commands/review.rb             resolve a folder argument
lib/planner/commands/run.rb                resolve a folder argument; PLAN-<N>.md name check
lib/planner/commands/summarise.rb          resolve a folder argument
lib/planner/cli.rb                         usage text
spec/planner/latest_file_spec.rb           new
spec/planner/commands/plan_spec.rb         folder examples
spec/planner/commands/explore_spec.rb      folder examples
spec/planner/commands/review_spec.rb       folder examples
spec/planner/commands/run_spec.rb          folder examples, name check examples
spec/planner/commands/summarise_spec.rb    folder examples
README.md                                  usage bullets
docs/GLOSSARY.md                           latest file entry
docs/TODO.md                               remove two items, add one
```

## Implementation

Follow the `writing-rspec` skill for every spec you add.

### `lib/planner/latest_file.rb` (new)

A module with one public method:

```ruby
# frozen_string_literal: true

module Planner
  # The file a command uses when it is given a plan folder instead of a file.
  module LatestFile
    # Any numbered plan folder file: its kind, number and letters.
    NAME = /\A(?<kind>[A-Z]+)-(?<number>\d+)(?:-(?<letters>[a-z]+))?\.md\z/

    # path itself when it is not a folder. Otherwise the folder's file whose name matches accepted with the
    # highest number, then the last letter. kinds names the accepted files in errors, e.g. "PLAN-<N>.md".
    def self.resolve(path, accepted, kinds)
      return path unless File.directory?(path)
      ...
    end
  end
end
```

Behaviour of `resolve` when `path` is a folder:

1. Take the names of the regular files directly in the folder (`Dir.children`, keep
   `File.file?`) that match `accepted` (the calling command's own name regex). Parse each
   with `NAME`.
2. If there are none, raise `Error, "#{path} has no #{kinds} file"`.
3. Keep those with the highest number, compared as integers.
4. Group them by kind and take the last of each group, ordering letters as base (no letters)
   first, then by letter length, then alphabetically (`a` … `z`, `aa` …).
5. If more than one kind is left, raise
   `Error, "#{path} has more than one latest file: #{names.sort.join(', ')}; give the file instead"`.
6. Return `File.join(path, name)`.

A path that is neither a file nor a folder is returned unchanged, so the commands' existing
"is not a" / "does not exist" errors still apply.

Add `require_relative 'planner/latest_file'` to `lib/planner.rb` after
`require_relative 'planner/table_of_content'`.

### Commands

In each command, replace `file = args.first` with a call to `LatestFile.resolve` and leave
the rest of the flow unchanged, so the resolved file goes through the existing name and
existence checks. Put each command's kinds text in a constant and use it in both the
existing "is not a" error and the `resolve` call, so the two cannot drift.

- `Plan`: after the `UsageError` check on the raw argument,
  `file = LatestFile.resolve(args.first, ITERATION_NAME, KINDS)` with
  `KINDS = 'ITERATION-<N>.md'`. The error becomes `"#{file} is not an #{KINDS} file"`.
- `Explore`: the same, with its own `ITERATION_NAME` and `KINDS = 'ITERATION-<N>.md'`.
- `Review`: `KINDS = 'PLAN-<N>.md or FINDINGS-<N>.md'`, resolved with `SOURCE_NAME`.
- `Summarise`: `KINDS = 'PLAN-<N>.md, REVIEW-<N>.md or FINDINGS-<N>.md'`, resolved with
  `SOURCE_NAME`.
- `Run`: add `PLAN_NAME = /\APLAN-\d+\.md\z/` and `KINDS = 'PLAN-<N>.md'`. Resolve with
  `PLAN_NAME`, then raise `Error, "#{file} is not a #{KINDS} file"` unless the basename
  matches, before the existing `does not exist` check. This applies with and without
  `--print`. If RuboCop flags `call`'s complexity, move the resolve and both checks into a
  private method, as `Summarise#source_number` does.

Every existing error message must stay byte-for-byte the same.

### `lib/planner/cli.rb`

Change these usage lines (keep the column alignment):

```
planner plan <iteration-file|plan-folder>
planner run [--model <model>] [--print] <plan-file|plan-folder>
planner review [--model <model>] [--lens <text>|-] <file|plan-folder>
planner explore [--model <model>] [--deep] <iteration-file|plan-folder>
planner summarise [--model <model>] [--brief <text>|-] <file|plan-folder>
```

### Specs

`spec/planner/latest_file_spec.rb`: specs run in a temp dir (see `spec_helper.rb`). Cover:
a non-folder path is returned unchanged (existing file and missing path); the highest number
wins, compared as integers (`PLAN-010.md` over `PLAN-009.md`); files of other kinds are
ignored (`run`'s case: `PLAN-002.md` chosen over `ITERATION-003.md`); last letter wins
(`FINDINGS-002-b.md` over `-a` and base, `-aa` over `-z`); a tie across kinds raises the tie
error naming both files alphabetically; no matching file raises the no-file error; a
subfolder is ignored.

In each command spec, add: a folder argument hands the agent the latest file (check the
file passed or named in the prompt); a folder with no suitable file raises that command's
no-file error. In `review_spec.rb` and `summarise_spec.rb` also add the tie error. In
`run_spec.rb` add: `notes.md` raises `notes.md is not a PLAN-<N>.md file`, with and without
`-p`; `nope.md` now raises `nope.md is not a PLAN-<N>.md file`, so update the two existing
`nope.md does not exist` examples to use a missing `PLAN-009.md` instead.

### `README.md`

The working tree already has the user's own README fix; edit on top of it and keep it. Load
the `update-readme` skill. In the `plan`, `run`, `review`, `explore` and `summarise` bullets,
change the argument to match the new usage lines, and add one short clause to each saying a
plan folder can be given instead, in which case it uses the highest-numbered
`ITERATION` / `PLAN` / `PLAN` or `FINDINGS` / `PLAN`, `REVIEW` or `FINDINGS` file. Note
that `review` currently shows `<plan-file>` and only mentions `PLAN-<N>.md`: change it to
`<file|plan-folder>` and say it takes a `PLAN-<N>.md` or `FINDINGS-<N>.md` file.

### `docs/GLOSSARY.md`

Add after the **table of contents** entry:

```
- **latest file**: The file `planner plan`, `explore`, `review`, `run` and `summarise` use when given a plan folder instead of a file: the one with the highest number among the kinds the command accepts, and the last letter among lettered files with that number. It is an error if the folder has none, or if files of two kinds share the highest number.
```

### `docs/TODO.md`

Load the `writing-todos` skill. Delete these two lines:

```
- Validate the file name passed to `run` (`PLAN-*.md`).
- If a folder is given to a file rather than a command chose the highest numbered file. Eg. for `explore` or `plan` chose the highest iteration number
```

Add at the end of the list:

```
- Rewrite the content of `README.md` in full so it is accurate and consistent, rather than patching it one bullet at a time. From [PLAN-001.md](plans/202611181357-run-latest-file/PLAN-001.md).
```

## Verification

1. `bundle exec rake` passes: all specs, including the new ones, plus RuboCop with no
   offences.
2. From the repo root, render the plan prompt for a folder with a fake agent that prints
   its argument:
   `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def plan(x) = puts(x) }.new; Planner::Commands::Plan.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- docs/plans/202611181357-run-latest-file`
   The output names `docs/plans/202611181357-run-latest-file/ITERATION-001.md` as the brief
   and `docs/plans/202611181357-run-latest-file/PLAN-001.md` as the plan file.
3. `ruby -Ilib -rplanner -e 'a = Struct.new(:p) { def default_run_model = "sonnet"; def run_tools = [] }.new; Planner::Commands::Run.new(Planner::Context.new(root: Pathname.pwd, home: Pathname.pwd, skills_dir: Pathname.pwd, agent: a, stdin: $stdin, stdout: $stdout, clock: -> { Time.now })).call(ARGV)' -- -p docs/plans/202611181357-run-latest-file`
   prints JSON whose prompt names
   `docs/plans/202611181357-run-latest-file/PLAN-001.md`.
4. The same command with `-- -p docs/plans/202611181357-run-latest-file/ITERATION-001.md`
   raises `Planner::Error` with
   `docs/plans/202611181357-run-latest-file/ITERATION-001.md is not a PLAN-<N>.md file`.
5. The same command with `-- -p lib` raises `Planner::Error` with
   `lib has no PLAN-<N>.md file`.

None of these steps write anything.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/latest_file.rb lib/planner.rb lib/planner/commands/plan.rb lib/planner/commands/explore.rb lib/planner/commands/review.rb lib/planner/commands/run.rb lib/planner/commands/summarise.rb lib/planner/cli.rb spec/planner/latest_file_spec.rb spec/planner/commands/plan_spec.rb spec/planner/commands/explore_spec.rb spec/planner/commands/review_spec.rb spec/planner/commands/run_spec.rb spec/planner/commands/summarise_spec.rb README.md docs/GLOSSARY.md docs/TODO.md docs/plans/202611181357-run-latest-file/ITERATION-001.md docs/plans/202611181357-run-latest-file/PLAN-001.md
```

`README.md` includes the user's earlier merge-conflict fix; commit it with this change.

Write the message to a file and commit with `git commit -F <file>`. The message follows the
`commit-message` skill's rules: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Let commands take a plan folder

planner plan, explore, review, run and summarise can now be given a
plan folder instead of a file. They use the highest-numbered file of
the kinds they accept, and stop with an error when the folder has no
such file or when two kinds share the highest number. This saves
typing the file name for the usual case of working on the latest
iteration.

planner run now also checks that it was given a PLAN file.

The README, glossary and todo list are updated to match, and the
README merge leftovers are cleaned up.

Assisted-by: <agent> (<model>)
```

## Deviations

- RuboCop Metrics/AbcSize failed on `latest_per_kind` because the plan's single-method shape was too complex; changed `lib/planner/latest_file.rb` to split it into private helpers `highest` and `last_letters`.
- RuboCop RSpec/ExampleLength failed on the new `run_spec.rb` folder example because it was six lines; changed `spec/planner/commands/run_spec.rb` to write the files straight into the folder.

---

## Stats

| Field | Value |
| --- | --- |
| Status | Completed |
| Started | 2026-11-18T14:13:10Z |
| Finished | 2026-11-18T14:15:30Z |
| Elapsed | 2m 20s |
| Model | sonnet |
| Tokens | ~60k (estimate) |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `sed -i "s/.../" spec/planner/commands/run_spec.rb` | BSD sed rejected the in-place flag form and the edit did not apply; redone with the Edit tool | Use the Edit tool, or `sed -i ''` on macOS |
