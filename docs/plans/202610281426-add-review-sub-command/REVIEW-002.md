# REVIEW-002 — docs/plans/202610281426-add-review-sub-command/PLAN-002.md

## Summary

The plan is accurate and its design holds up. The template text, the ERB trimming, the spec
examples and the README clause all render or behave the way the plan says. However, all three
changes are already in the working tree and committed. The latest commits include one with the
plan's suggested subject, "Give the planner review summary a fixed format" (7b0c9b6), and git
status shows nothing pending in these files. A developer following the plan would find the
"delete the last two lines" step has nothing to delete, and the commit step would have nothing
to commit. Verification step 2 also now expects the wrong review file name, because this review
creates `REVIEW-002.md`.

## High-confidence findings

1. **The plan is already implemented, so the steps no longer apply as written.**
   - `lib/planner/prompts/review.md.erb:55-80` already holds the "Summary for the user" section,
     and it matches the plan's template text (PLAN-002.md:55-80) exactly.
   - The closing lines the plan says to delete ("When the file is written, give the user a short
     plain-English summary of the review here.", PLAN-002.md:44-47) are no longer in the file.
   - `spec/planner/commands/review_spec.rb:105-115` and `:132-136` already contain all three new
     examples word for word.
   - `README.md:20` already has the clause "then summarise it in the session under the same
     headings".
   - The latest commits include 7b0c9b6, "Give the planner review summary a fixed format", which
     is the plan's suggested commit subject (PLAN-002.md:165). The session's git status lists no
     changes to any of these files.

   As a result, the `git commit -F <file> -- …` step (PLAN-002.md:159) would fail with "nothing
   to commit". The plan should either be marked as done or say how to confirm the existing state
   rather than re-apply it.

2. **Verification step 2 expects the wrong review file name once a review exists.**
   PLAN-002.md:139-141 says the rendered format starts with
   ``Review written to `docs/plans/202610281426-add-review-sub-command/REVIEW-002.md`.``.
   `Commands::Review#review_file` (`lib/planner/commands/review.rb:30-39`) picks the first free
   name, so it moves to `REVIEW-002-a.md` when `REVIEW-002.md` already exists. That file now
   exists because of this review, so the hand-rendered prompt will show `REVIEW-002-a.md` and the
   check as written will fail. The expectation should be `REVIEW-002<suffix>.md`, or the step
   should point at a throwaway plan file under the scratchpad directory.

## Lower-confidence concerns

1. **The README wording is slightly loose.** `README.md:20` says the summary uses "the same
   headings". The template (`lib/planner/prompts/review.md.erb:60-77`) uses bold labels, not
   headings, and adds a `Review written to …` line. A reader probably won't be misled, but "the
   same sections" or "a fixed short format" would be more accurate.

2. **The commit message file location is not given.** PLAN-002.md:156 says "Write the message to
   a file" but doesn't say where. The scratchpad directory is the obvious choice, and the plan
   could say so. This is minor and moot while finding 1 stands.

3. **Verification doesn't cover the README.** Neither verification step checks the README edit.
   It is a one-line prose change, so `bundle exec rake` plus a visual check is probably enough.
   A one-line "confirm `README.md:20` contains the clause" step would close the gap.

## Top recommendations

1. Mark PLAN-002 as already implemented in 7b0c9b6, or change its steps to "confirm the existing
   state" rather than edit and commit.
2. Fix Verification step 2 so it doesn't hard-code `REVIEW-002.md`. Either allow the `-a`
   suffix or render against a throwaway plan in the scratchpad.
3. Optionally tighten the README wording from "headings" to "sections".
