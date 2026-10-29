# Glossary

- **plan folder**: A directory at `docs/plans/<YYYYMMDDHHMM>-<slug>/` that holds the iteration and plan files for one piece of work. Created by `planner new`.
- **iteration file**: `ITERATION-<NNN>.md`. The brief for one iteration of work.
- **plan file**: `PLAN-<NNN>.md`. The implementation plan written from an iteration file by `planner plan`.
- **review file**: `REVIEW-<NNN>.md`, or `REVIEW-<NNN>-<letter>.md` for a later review of the same plan. A plain-English review of a plan file, written by `planner review`.
- **findings file**: `FINDINGS-<NNN>.md`, or `FINDINGS-<NNN>-<letter>.md` for a later exploration of the same iteration. Answers to the questions in an iteration file, found by exploring the code or data. Written by `planner explore`, and never executed.
- **skill**: A folder under `lib/planner/skills/<slug>/` with a `SKILL.md`, for the agent to use. Copied into `.claude/skills` by `planner skills install`.
- **agent**: The coding tool planner hands off to. Currently `claude`.
