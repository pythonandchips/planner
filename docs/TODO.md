# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- `planner new` should also create `ITERATION-001.md` in the new plan folder.
- Validate the file name passed to `run` (`PLAN-*.md`).
- Find the project root from the git top-level instead of cwd.
- Add rules for run with commit discipline around content of commit message and PR body
- allow the review command to edit a plan
- Ship the first skills under `lib/planner/skills` (for example writing git commits, running yarn commands).
- Add a skill to update the plan when doing a review.
- Allow the review fill to be commited even when it is not part of the plan
