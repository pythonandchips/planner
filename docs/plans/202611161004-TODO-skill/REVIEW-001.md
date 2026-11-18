# REVIEW-001 — docs/plans/202611161004-TODO-skill/PLAN-001.md

## Summary

The plan is clear and mostly matches the code. `SkillCatalog`, the gemspec, `planner skills
list` and the specs it names all behave as it says, the glossary anchor exists, and the global
todo example links to a real findings file. The main problems are in Verification and in the
"same as `writing-erb`" precedent: step 6 cannot pass as written because `docs/TODO.md`
already has an uncommitted change and `git diff --stat` does not show new, untracked files;
`writing-erb` never shipped an `evals/evals.json`, so committing one here is new and puts it
in the gem and in every install; and `README.md` has a leftover merge conflict marker next to
the section the developer will edit, which the plan does not mention.

## High-confidence findings

1. **Verification step 6 cannot pass as written** (`PLAN-001.md:205-206`). The git status at
   the start of this session shows `M docs/TODO.md`: the file already has an uncommitted
   change in the working tree (its last few items, `docs/TODO.md:10-13`, read like recent
   additions). So `git diff --stat` will list `docs/TODO.md` before the developer has done
   anything, and "`docs/TODO.md` is unchanged" fails. Separately, `git diff --stat` only
   shows changes to tracked files, so the new `lib/planner/skills/writing-todos/` files will
   not appear in it at all until they are staged. Suggest: compare against the start of the
   run with `git status --short` instead, say that the existing change to `docs/TODO.md` is
   expected and must be left alone, and check the new folder with `git status` rather than
   `git diff --stat`.

2. **`writing-erb` is not a precedent for committing `evals/evals.json`** (`PLAN-001.md:30`,
   `PLAN-001.md:41`, `PLAN-001.md:127`). No shipped skill has an evals file: the only files
   under `lib/planner/skills/` are the four `SKILL.md` files. The `writing-erb` plan did
   ask for `evals/evals.json`
   (`docs/plans/202611051233-add-erb-writing-skill/PLAN-001.md:35`), but its run stopped at
   the commit step (`...add-erb-writing-skill/PLAN-001.md:236-243`) and the file is not in
   the repo. So "Only `SKILL.md` and `evals/evals.json` are committed", described as the
   `writing-erb` process, is new behaviour, not a copy of what exists.

   **Applied:** The Build process decision now says only `SKILL.md` is committed, as with the shipped `writing-erb`, and no longer claims `writing-erb` committed evals.

3. **`evals/evals.json` would ship in the gem and be installed into users' projects**
   (`planner.gemspec:17`, `lib/planner/commands/skills/install.rb:74`). The gemspec packs
   every file under `lib/planner/skills/**/*`, and `planner skills install` copies the
   whole skill folder with `FileUtils.cp_r`. So the evals, with their inline todo files
   and review text, end up in every `.claude/skills/writing-todos/` that is installed. The
   plan says the skill "ships in the gem" but does not say whether the evals should. If
   they should not, they need to live outside `lib/planner/skills/` (or the gemspec and
   `Install` need to skip them, which this plan rules out by saying no Ruby changes).

   **Applied:** Evals now go in `$TMPDIR/writing-todos-workspace/evals/evals.json` and are not committed; the files list, steps 1 and 2, Verification 4 and 5, and the staging list were updated to match.

4. **`README.md` has a leftover merge conflict marker that the plan does not mention**
   (`README.md:22`). Line 22 is `||||||| parent of 583842a (Let planner review run over
   FINDINGS files)`, and lines 20-24 now have two versions each of the `planner review` and
   `planner explore` bullets. Step 4 tells the developer to follow
   `.claude/skills/update-readme/SKILL.md`, whose step 4 says "Delete what the change made
   untrue" (`.claude/skills/update-readme/SKILL.md:17`), so a developer may tidy this up,
   or may ask whether to. Either way the README diff would no longer be the single bullet
   the plan expects. The plan should say whether to leave these lines alone or fix them,
   and if fixing, which version of each bullet to keep.

   **Applied:** Step 4 and the README decision now say to leave `README.md:20-24` as they are, so the only README change is the new bullet.

## Lower-confidence concerns

1. **The pause for user review is in the Decisions table but not in the steps**
   (`PLAN-001.md:30` vs `PLAN-001.md:129-148`). Decisions lists "pause for user review in
   the viewer", but Implementation step 2 only says to run, grade and iterate. A developer
   following the steps could skip the pause. The `writing-erb` run also found that the
   viewer could not open itself in the sandbox and that `timeout` is not on macOS
   (`...add-erb-writing-skill/PLAN-001.md:250-252`). Step 2 could say to hand the viewer URL
   to the user and wait, and not to use `timeout`.

   **Applied:** Step 2 now says to pause for user review after each run, hand over the viewer URL or `--static` path, read `feedback.json` by path, and not use `timeout`.

2. **Plan folders outside `docs/plans/` are not covered** (`PLAN-001.md:79-81`,
   `PLAN-001.md:93-95`). `planner new --dir` can put a plan folder anywhere
   (`README.md:17`), but the source-link rule only spells out the path for "a plan folder
   under `docs/plans/`". The skill text should say the link is simply the path relative to
   `docs/TODO.md`, whatever folder the plan is in, and how the agent tells that a folder is
   a plan folder (for example, it holds `ITERATION-*.md` or `PLAN-*.md` files).

3. **A new plan todo leaves an existing table of contents out of date**
   (`PLAN-001.md:32`). The table of contents does put an unnumbered `TODO.md` in its `Other`
   group (`lib/planner/prompts/_table_of_content.md.erb:37`, `:59`), but only when `planner
   toc` or another planner command rewrites it. When the skill creates `TODO.md` in a folder
   that already has `TABLE-OF-CONTENT.md`, the file will not be listed until then. This may
   be fine, but the plan should say so.

4. **Verification step 3 adds a rule that Implementation does not state**
   (`PLAN-001.md:195`). "Mentions no other skill" is checked in Verification but is not one
   of the rules in Implementation step 1. Either add it to step 1 or drop it from the check.

5. **The Commit section gives no commit mechanics** (`PLAN-001.md:211-238`). Unlike the
   `writing-erb` plan (`...add-erb-writing-skill/PLAN-001.md:202-213`), it does not say to
   run each git command on its own, write the message to a file and use `git commit -F`,
   or follow the `commit-message` skill with an `Assisted-by:` trailer. The suggested
   message has no trailer. A careful developer will likely do this anyway, but the
   precedent shows commit steps are where these runs stop.

   **Applied:** The Commit section now says to run each git command alone, commit with `git commit -F` from a file in `$TMPDIR`, follow the `commit-message` skill, and the suggested message ends with an `Assisted-by:` trailer.

6. **"When it is not obvious, why" and "at most three sentences" may pull against each
   other in eval 4** (`PLAN-001.md:144-145`). The expected result says only "saying what
   needs doing", so a grader may mark down an item that also gives a reason. Saying whether
   the why counts towards the three sentences would make the grading clear.

## Top recommendations

1. Rewrite Verification step 6 to use `git status --short`, and say the existing uncommitted
   change to `docs/TODO.md` is expected and must not be touched or staged.
2. Decide whether `evals/evals.json` should ship in the gem and be installed; if not, keep
   the evals out of `lib/planner/skills/`, and either way drop the claim that `writing-erb`
   committed one.

   **Applied:** Evals are kept in the `$TMPDIR` workspace and not committed or shipped, and the claim that `writing-erb` committed one is gone.

3. Tell the developer what to do about the conflict marker at `README.md:22`.

   **Applied:** Step 4 says to leave the conflict lines at `README.md:20-24` as they are.

4. Move "pause for user review, hand over the viewer URL, and do not use `timeout`" into
   Implementation step 2.

   **Applied:** Step 2 now has the pause, the viewer URL hand-over, reading `feedback.json` by path, and the ban on `timeout`.

5. Add commit mechanics (`git commit -F`, `commit-message` skill, `Assisted-by:` trailer)
   to the Commit section.

   **Applied:** The Commit section now has one git command per call, `git commit -F`, the `commit-message` skill and an `Assisted-by:` trailer in the suggested message.
