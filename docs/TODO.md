# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- Spawn `claude` and wait for it instead of `exec`, so post-run static checks can run afterwards.
- `planner new` should also create `ITERATION-001.md` in the new plan folder.
- Validate the file names passed to `plan` (`ITERATION-*.md`) and `run` (`PLAN-*.md`).
- Find the project root from the git top-level instead of cwd.
- Bundle the `plan-from-iteration` skill (now in `docs/examples/plan-from-iteration-skill.md`) into planner so the command doesn't rely on a separately installed skill.
