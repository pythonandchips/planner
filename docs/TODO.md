# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- Spawn `claude` and wait for it instead of `exec`, so post-run static checks can run afterwards.
- `planner new` should also create `ITERATION-001.md` in the new plan folder.
- Validate the file name passed to `run` (`PLAN-*.md`).
- Find the project root from the git top-level instead of cwd.
- After `planner run`, check that the agent followed the plan (for example, compare the diff against the plan's file list).
- Add rules for run with commit discipline around content of commit message and PR body
- allow the review command to edit a plan
- Ship the first skills under `lib/planner/skills` (for example writing git commits, running yarn commands).
- add a verification skill for this repo to stop it tying to install the gem. It will not be allowed to do that.
- Add a skill to update the plan when doing a review.
- Add an instruction to run to mark the plan as implemented once complete
