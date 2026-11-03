# planner

Creates plan folders and hands iteration files and plan files to an agent.

## Install

```sh
bundle install && bundle exec rake install
```

Run `mise reshim` afterwards if you use mise shims.

## Usage

Run from the project root.

- `planner new <given-name>`: create a plan folder under `docs/plans/` and print its path.
- `planner plan <iteration-file>`: take an `ITERATION-<N>.md` file and have the agent write the matching `PLAN-<N>.md` next to it.
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file exactly, stopping to explain if it can't, and append stats (status, elapsed time, estimated tokens, commands that needed help) to the plan file (default model `sonnet`).
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it, then summarise it in the session under the same headings; `--lens` narrows the review, `--lens -` reads the lens from stdin; ask in the session and it applies suggestions to the plan and marks each one `**Applied:**` in the review (default model `opus`).
- `planner explore [--model <model>] <iteration-file>`: have the agent answer an `ITERATION-<N>.md` brief by exploring the code or data in rounds, asking you about anything unclear and checking in after each round so you can steer it or finish, and write a read-only `FINDINGS-<N>.md` next to it that opens with a summary and advisory recommendations, then summarise it in the session (default model `opus`).
- `planner toc [--model <model>] <plan-folder>`: have the agent write `TABLE-OF-CONTENT.md` in a plan folder, replacing any existing one: a short summary of the work, then the files and folders grouped by number, each group with a one-line summary and, for plans, whether they are completed. Once it exists, `planner plan`, `explore`, `review` and `run` keep it up to date (default model `haiku`).
- `planner skills list`: list the skills planner ships.
- `planner skills install [--global] [--only <slug>,...]`: copy the skills into `.claude/skills`, or `~/.claude/skills` with `--global`; asks before replacing a skill that has changed.

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login
```

## Skills

These ship with planner and are installed with `planner skills install`.

- `commit-message`: makes the agent write commit messages in plain English, with a body that says what changed and why, an `Assisted-by:` trailer instead of `Co-Authored-By:`, and the usual subject and wrapping rules.
- `writing-rspec`: makes the agent write spec descriptions that say what the code does, not how, in the present tense without "should", and use separate `expect` lines instead of `.and` matchers.

## Development

```sh
bundle exec rake  # specs, then RuboCop
```
