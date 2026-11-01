# Glossary

- **plan folder**: A directory at `docs/plans/<YYYYMMDDHHMM>-<slug>/` that holds the iteration and plan files for one piece of work. Created by `planner new`.
- **iteration file**: `ITERATION-<NNN>.md`. The brief for one iteration of work.
- **plan file**: `PLAN-<NNN>.md`. The implementation plan written from an iteration file by `planner plan`.
- **review file**: `REVIEW-<NNN>.md`, or `REVIEW-<NNN>-<letter>.md` for a later review of the same plan. A plain-English review of a plan file, written by `planner review`. When the user has the review session apply suggestions to the plan, each applied item gets an `**Applied:**` line.
- **findings file**: `FINDINGS-<NNN>.md`, or `FINDINGS-<NNN>-<letter>.md` for a later exploration of the same iteration. Answers to the questions in an iteration file, found by exploring the code, data or web pages. It opens with a summary and recommendations. It is rewritten after each round of exploration, and gets its stats when you finish. Written by `planner explore`, and never executed.
- **table of contents**: `TABLE_OF_CONTENT.md` in a plan folder. A short plain-English summary of the folder's work, then its files and folders grouped by number, each group with a one-line summary, and `Completed` or `Not completed` on each plan file. Entries without a number go in a final `Other` group. Written by `planner toc`, and updated by `planner plan`, `planner explore`, `planner review` and `planner run` when it exists.
- **skill**: A folder under `lib/planner/skills/<slug>/` with a `SKILL.md`, for the agent to use. Copied into `.claude/skills` by `planner skills install`.
- **agent**: The coding tool planner hands off to. Currently `claude`.
- **summary**: The plain-English account of what the agent found. `planner explore` writes it as `## Summary` at the top of the findings file, and after `planner explore` or `planner review` writes its file the agent also gives one in the session.
- **recommendations**: The `## Recommendations` section near the top of a findings file: further exploration, or actions a later iteration could plan, each citing the findings it follows from. Advisory only: nothing in it has been decided.
- **stats**: The `## Stats` block the agent adds to a file it writes: model, estimated tokens, and the commands that needed help. `planner run` also records status and timings. Appended to the plan file by `planner run` and to the findings file by `planner explore`.
