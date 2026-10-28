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
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file exactly, stopping to explain if it can't (default model `sonnet`).
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it; `--lens` narrows the review, `--lens -` reads the lens from stdin (default model `opus`).

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login
```

## Development

```sh
bundle exec rake  # specs, then RuboCop
```
