# REVIEW-001 — docs/plans/202611102006-summarise-command/PLAN-001.md

## Summary

The plan is detailed and mostly matches the code. It follows `Commands::Review` closely, names
real files, methods and insertion points, and its Verification commands point at files that
exist. But Verification step 1 (`bundle exec rake`) will not pass as written. One new spec
example checks for text the template does not contain. The command uses a safe-navigation
chain that RuboCop 1.92 flags. Two new spec examples go over the repo's 5-line
`RSpec/ExampleLength` limit. Two docs lines that list the commands which update the table of
contents are also left out of date.

## High-confidence findings

1. **The "rules" spec example fails: the template has no line break inside "full reference".**
   The spec at PLAN-001.md:490-493 expects `"full\nreference"`, and PLAN-001.md:585-586 says
   this "matches the template's line wrap between those two words". In the template the plan
   gives, the wrap falls before "full", not after it: PLAN-001.md:113-114 reads
   `the summary. Give every such piece of information a` / `full reference: ...`. So the
   prompt contains `"a\nfull reference"` and not `"full\nreference"`, and the example fails.
   Fix it by changing the expectation to `'full reference'` and deleting or correcting the
   note at line 585.

   **Applied:** The spec now expects `'full reference'`, and the note about the line wrap is deleted.

2. **`Style/SafeNavigationChainLength` flags `Summarise#call`.** PLAN-001.md:243 uses
   `File.basename(file).match(SOURCE_NAME)&.captures&.compact&.first`, which has three `&.`
   calls. The repo runs RuboCop 1.92.1 (`Gemfile.lock:36`) with `NewCops: enable`
   (`.rubocop.yml:7`). That cop is on by default with `Max: 2`, so `bundle exec rake` reports
   an offence. One fix keeps the meaning with two `&.` calls:
   `File.basename(file).match(SOURCE_NAME)&.captures&.find(&:itself)`.

   **Applied:** The number is now extracted with `match(SOURCE_NAME)&.captures&.find(&:itself)`.

3. **Two new examples go over `RSpec/ExampleLength` (Max 5).** The repo uses the default
   limit and disables the cop inline when an example runs longer
   (`spec/planner/commands/explore_spec.rb:112,124,136,145`). Each of these examples has six
   non-blank lines:
   - "accepts review and findings files, lettered or not" (PLAN-001.md:415-423): the `each`
     line, `File.write`, `agent.calls.clear`, `command.call`, `expect` and `end`.
   - "rejects a file that cannot be summarised" (PLAN-001.md:562-570): the `each` line,
     `File.write`, a three-line `expect`, and `end`.

   RuboCop fails on both. Shorten them, for example by reading `agent.calls.last` instead of
   clearing the calls, or by fitting the `raise_error` on fewer lines. Otherwise add
   `# rubocop:disable RSpec/ExampleLength` as explore_spec does.

4. **The docs that list who updates the table of contents become out of date.** Summarise
   updates `TABLE-OF-CONTENT.md` (Decisions, PLAN-001.md:33). But `README.md:22` says "Once
   it exists, `planner plan`, `explore`, `review` and `run` keep it up to date", and
   `docs/GLOSSARY.md:8` says it is "updated by `planner plan`, `planner explore`,
   `planner review` and `planner run`". The plan only adds a usage bullet and a glossary
   entry. The `update-readme` skill it tells the developer to follow says "Delete what the
   change made untrue" (`.claude/skills/update-readme/SKILL.md:17`). Add `summarise` to both
   lines.

   **Applied:** The README and GLOSSARY sections now add `summarise` to the toc bullet and the table of contents entry, and the Docs decision and file list mention it.

## Lower-confidence concerns

1. **Binary output can only be written through Bash, outside the Edit permission rules.**
   The `--allowedTools=Edit(<base>.*),…` rules (PLAN-001.md:322) cover the Write tool, which
   writes text. Formats the brief invites, such as `.gif`, `.mp3` and `.pptx`
   (PLAN-001.md:132-133 and the README bullet), have to be made by a Bash command like
   `ffmpeg` writing the file. Edit rules do not cover that. The Decisions accept that Bash
   prompts each time. Still, "only the summary path is written" (PLAN-001.md:31) then rests
   on the prompt and the user's approval, not on permissions. A sentence in the plan saying
   so would stop a developer from thinking the allow-list enforces it.

   **Applied:** Added a paragraph after the `claude.rb` steps: the prompt and the user's approval of each Bash command, not the Edit allow-list, keep Bash-made output to the summary path.

2. **Sandboxing may block `mktemp -d`.** Rule 3 (PLAN-001.md:93-95) tells the agent to use
   `mktemp -d`, which creates the directory under `$TMPDIR`, outside the repo. If the
   sandbox in the user's Claude Code setup does not allow writes there, every multi-step
   media brief hits a blocked command. That gets reported under "Commands that needed help",
   but nothing in the plan checks it in advance.

3. **The Skill tool is not pre-allowed.** `SUMMARISE_TOOLS` includes `Skill` for
   `commit-message` (PLAN-001.md:316), but `--allowedTools` leaves it out, so loading the
   skill may prompt. That may be intended, since commits only happen on request. It is not
   stated.

4. **Verification never exercises the real `claude` call.** Steps 2-4 (PLAN-001.md:656-672)
   use a fake agent, and the `claude_spec` example only compares argv. Nothing checks that
   `Edit(docs/…/SUMMARY-001.*)` and `Edit(docs/…/SUMMARY-001/**)` behave as Claude Code
   permission patterns in practice. Review and explore have the same gap, so this is
   consistent, but these two patterns are the first globbed ones.

5. **"Write the output at most once" is unclear for folder output.** Rule 5
   (PLAN-001.md:99-102) says "Once anything is written, write nothing more". A
   `SUMMARY-<NNN>/` folder holds several files, and the TOC is updated after the summary, so
   both mean more than one write. The intent is clear, but an agent reading it literally
   could stop after the first file. Wording such as "Produce the output in one go; after
   that, write nothing more except the table of contents" would be safer.

6. **The no-brief prompt still carries the on-disk instructions.** With no brief, the
   template says "Write nothing to disk" (PLAN-001.md:79-81). But it still renders the
   "Committing" section, the on-disk reply format and the TOC update rules
   (PLAN-001.md:145-215). That is harmless, but the agent gets instructions it must not use.

## Top recommendations

1. Change the "rules" spec expectation to `'full reference'` and fix the note at
   PLAN-001.md:585.

   **Applied:** The spec now expects `'full reference'`, and the note is deleted.

2. Rewrite the number extraction in `Summarise#call` with at most two `&.` calls, for example
   `&.captures&.find(&:itself)`.

   **Applied:** `Summarise#call` now uses `match(SOURCE_NAME)&.captures&.find(&:itself)`.

3. Shorten the two six-line spec examples, or add inline `RSpec/ExampleLength` disables as
   `explore_spec.rb` does.
4. Add `summarise` to the lists of commands that update the TOC in `README.md:22` and
   `docs/GLOSSARY.md:8`.

   **Applied:** The plan now changes both lines to include `summarise`, and the Docs decision and file list mention it.

5. Note in the plan that Bash-made outputs are kept to the summary path by the prompt and
   the user's approval, not by the Edit allow-list.

   **Applied:** Added that note after the `claude.rb` steps.
