# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- `planner new` should also create `ITERATION-001.md` in the new plan folder.
- Validate the file name passed to `run` (`PLAN-*.md`).
- Find the project root from the git top-level instead of cwd.
- Add rules for run with commit discipline around content of commit message and PR body
- Ship more skills under `lib/planner/skills` (for example running yarn commands).
- Allow the review fill to be commited even when it is not part of the plan
- limit the plan and review to only read the files in the same folder. Not files in other `docs/plans`
- Have plan ignore files that are gitignored for staging
