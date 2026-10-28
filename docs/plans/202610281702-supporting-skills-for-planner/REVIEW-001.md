# REVIEW-001 — docs/plans/202610281702-supporting-skills-for-planner/PLAN-001.md

## Summary

The plan is in good shape. What it says about the existing code is accurate. `UsageError` is
currently an empty subclass (`lib/planner/errors.rb:8`). `Context` has the five members the plan
expects (`lib/planner/context.rb:5`). The CLI's `COMMANDS`, `USAGE` and the `rescue UsageError`
are where the plan says (`lib/planner/cli.rb:6-11`, `13-18`, `29-31`). The require list in
`lib/planner.rb:3-17` matches the plan's insertion points. The gemspec `files` glob is at
`planner.gemspec:17`. `exe/planner:6-12` builds the context the plan describes. The plan lists all
five specs that call `Context.new`, and no others call it.

The new code follows the existing idioms: `OptionParser` with `parse!` and
`rescue OptionParser::ParseError` → `UsageError`, as in `lib/planner/commands/review.rb:55-65`.
I traced the trickier parts and they work. `raise UsageError, USAGE` reaches the new
`initialize(usage = nil)` through `Exception.exception`. The load order lets `SUBCOMMANDS` name
`Skills::List` and `Skills::Install`. `--only` is checked before any prompt, and a declined
prompt leaves everything untouched. The decisions table and the code agree on every point I
checked.

The main gaps are small:
- the YAML rescue is too narrow;
- one manual verification step is interactive and gives no way to feed it an answer;
- the commit step will also stage this review file;
- two rules may conflict for spec lines that get longer.

All three high-confidence findings have since been applied to the plan; see
**Changes applied** at the end. The lower-confidence concerns are still open.

## High-confidence findings

1. **`SkillCatalog.frontmatter` only rescues `Psych::SyntaxError`, but `YAML.safe_load` raises
   other errors too.** *(Applied.)* In the plan's `lib/planner/skill_catalog.rb` (plan lines 123-129),
   frontmatter that is valid YAML but holds a date (`created: 2026-10-28`), a symbol or an alias
   raises `Psych::DisallowedClass` or `Psych::AliasesNotEnabled`. Neither of these is a
   `Psych::SyntaxError`; both inherit from `Psych::Exception`. The error escapes `SkillCatalog.all`
   and crashes `planner skills list` and `install` with a Ruby backtrace, not a blank description.
   This breaks the decision at plan line 40 ("broken YAML ... gives a blank description"). Only
   shipped skills are ever read, so the shipped-skill spec would catch it before release, but the
   failure would show up as a confusing spec error. Fix: `rescue Psych::Exception`, and add a
   spec case such as `date: 2026-01-01`.

2. **Verification step 3 needs interactive answers and doesn't say how to give them.**
   *(Applied.)* Plan lines 435-436 say "run again, answer `n`" and "answer `y`". Plans are
   carried out by `planner run` (an agent), which can't type at a prompt. The step should give
   the command, for example `printf 'n\n' | planner skills install` and
   `printf 'y\n' | planner skills install`. Otherwise the developer has to work it out, or the
   step gets skipped.

3. **The commit's `git add` stages more than the plan says.** *(Applied.)* Plan line 449 adds
   the whole plan folder, and line 452 says this stages "`ITERATION-001.md` and `PLAN-001.md`".
   It will also stage this `REVIEW-001.md`, plus any other file in the folder. No earlier plan
   folder has a committed review file (`docs/plans/*/` contains only `ITERATION-*` and
   `PLAN-*`). The plan should either name the two files or say that the review is meant to be
   committed.

## Lower-confidence concerns

1. **Spec line length and "change nothing else".** The plan adds about 60 characters to every
   existing `Context.new` call (plan lines 337-340) and forbids any other change to those
   files. `spec/planner/commands/review_spec.rb:9` and `spec/planner/cli_spec.rb:9` are about
   108-113 characters now and will go past RuboCop's default 120. `plan_spec.rb:7` and
   `run_spec.rb:7` are already about 135 characters, so this repo may not enforce the limit in
   practice; I couldn't run RuboCop to check. If it does, Verification step 1 ("no offences")
   conflicts with "change nothing else". The plan's permission to reshape code for RuboCop
   (line 299) is under `install.rb` only. Say explicitly that wrapping these lines is allowed.

2. **The `skills list` smoke test in `spec/exe/planner_spec.rb` depends on the state of the
   repo.** The spec runs `exe/planner` with `-I<repo>/lib`, so it reads the repo's
   `lib/planner/skills`. If someone runs `bundle exec rake` while the temporary `demo` skill
   from Verification step 3 exists, that example fails. The plan orders the steps correctly,
   but a note in step 3 ("don't run the specs while `demo` exists") would help. The plan
   already says the example must change when the first skill ships.

3. **The gemspec glob skips dotfiles.** `Dir['lib/planner/skills/**/*']` (plan line 331) doesn't
   match names starting with `.`. `cp_r` and `identical?` (with `FNM_DOTMATCH`) do include
   them. A future skill with a dotfile would install with that file when run from the repo but
   without it from the installed gem. This doesn't matter now because no skills ship.

4. **`identical?` compares only file lists and bytes.** A change to a script's permissions only
   (for example making `scripts/x.sh` executable) counts as `unchanged` and is never installed.
   This matches the stated decision (plan line 28), but nothing in the plan points out the
   consequence.

5. **Replacing a skill is not atomic.** `rm_rf` runs before `cp_r` (plan lines 274-275). If the
   copy fails partway, the user's previous copy is already gone. This is acceptable for a
   local tool, but it isn't listed as a known risk.

6. **`--only ""` or `--only ,` gives an empty selection.** `OptionParser`'s `Array` turns these
   into `[]`, so `choose` selects nothing, `install` still runs `mkdir_p`, and the command
   prints nothing and exits 0. No decision covers this case. It might be better treated as a
   usage error.

7. **`Dir.home` now runs for every command.** `exe/planner` builds the context eagerly, so if
   neither `HOME` nor a passwd entry is available, `Dir.home` raises `ArgumentError`. This
   would also break `planner new`, `plan`, `run` and `review`. That setup is rare, so this
   matters only in unusual CI containers.

8. **Behaviour the plan describes but no spec covers.** "A destination path that exists but is
   a file counts as a conflict" (plan line 297) has no spec. A one-line example would protect
   it.

9. **The frontmatter regex is strict.** `FRONTMATTER = /\A---\n(.*?)\n---\n/m` doesn't match CRLF
   line endings, or a closing `---` at the end of the file with no newline after it. Both
   quietly give a blank description. The shipped-skill spec would catch either one, so this is
   low risk.

10. **Option abbreviations and `--help`.** `OptionParser` accepts abbreviations (`--g` for
    `--global`, `--o` for `--only`). Its built-in `--help` prints an auto-generated banner and
    exits 0 without showing the skills usage. Existing commands (`review.rb`) already behave
    this way, and `docs/TODO.md:4` tracks `--help`, so this is consistent but worth knowing.

## Top recommendations

1. Change `rescue Psych::SyntaxError` to `rescue Psych::Exception` in `SkillCatalog.frontmatter`
   and add a spec for frontmatter with a date. *(Applied.)*
2. In Verification step 3, give the non-interactive commands (`printf 'n\n' | planner skills
   install`, `printf 'y\n' | ...`). *(Applied.)*
3. In the Commit section, name the files to stage, or say that `REVIEW-001.md` is meant to be
   committed. *(Applied.)*
4. Say explicitly that the edited `Context.new` lines in the existing specs may be wrapped to
   satisfy RuboCop.
5. Add a spec for a destination that exists as a plain file.

## Changes applied

The three high-confidence findings were applied to `PLAN-001.md` after this review was
written. Line numbers in the findings above refer to the plan before these edits.

1. **YAML rescue (finding 1).**
   - In the `lib/planner/skill_catalog.rb` code block, `rescue Psych::SyntaxError` became
     `rescue Psych::Exception`. The method comment now reads "or {} when it is missing or
     YAML.safe_load rejects it".
   - A short note after the code block explains that `Psych::Exception` covers
     `Psych::SyntaxError`, `Psych::DisallowedClass` and `Psych::AliasesNotEnabled`.
   - The "Description source" decision now says that YAML that fails to load gives a blank
     description. This covers broken YAML, and YAML using a class or alias that `safe_load`
     rejects, such as a date.
   - The `skill_catalog_spec.rb` blank-description example gained a case:
     `description: Dated` plus `created: 2026-01-01` gives `''`.
2. **Interactive verification (finding 2).** Verification step 3 now uses
   `printf 'n\n' | planner skills install` and `printf 'y\n' | planner skills install`. It also
   says what each run should print: the confirmation, then `[planner] Install cancelled` with
   exit 1 and the edit kept for `n`, and `installed demo -> .claude/skills/demo` with the file
   restored for `y`.
3. **Commit staging (finding 3).** The `git add` now names
   `docs/plans/202610281702-supporting-skills-for-planner/ITERATION-001.md` and `PLAN-001.md`
   instead of the whole folder. The text says to stage only those two files and no
   `REVIEW-*.md`, which matches earlier plan folders.

The plan is otherwise unchanged. Lower-confidence concerns 1-10 and recommendations 4-5 were
not applied.
