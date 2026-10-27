# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- Spawn `claude` and wait for it instead of `exec`, so post-run static checks can run afterwards.
- `planner new` should also create `ITERATION-001.md` in the new plan folder.
- Validate the file name passed to `run` (`PLAN-*.md`).
- Find the project root from the git top-level instead of cwd.
- After `planner run`, check that the agent followed the plan (for example, compare the diff against the plan's file list).
