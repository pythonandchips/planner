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
- `planner plan <iteration-file>`: have the agent write a plan file from an iteration file.
- `planner run [--model <model>] <plan-file>`: have the agent implement a plan file (default model `sonnet`).

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login
```

## Development

```sh
bundle exec rake  # specs, then RuboCop
```
