# planner

Creates plan folders and hands iteration files and plan files to an agent.

## Install

```sh
bundle install && bundle exec rake install
```

Run `mise reshim` afterwards if you use mise shims.

## Usage

Run from the project root.

- `planner new [--dir <folder>] <given-name>`: create a plan folder under `docs/plans/`, or under `--dir` (`-d`) relative to the project root, and print its path.
- `planner plan <iteration-file>`: take an `ITERATION-<N>.md` file and have the agent write the matching `PLAN-<N>.md` next to it; it asks whether the plan should end in a commit.
- `planner run [--model <model>] [--print] <plan-file>`: have the agent implement a plan file exactly, fixing failing verification steps and stopping to explain if it can't, and append deviations and stats to the plan file, committing only when the plan says to (default model `sonnet`); `--print` (`-p`) prints the prompt, model and allowed tools as JSON instead, for running with your own `claude` command.
- `planner review [--model <model>] [--lens <text>|-] <plan-file>`: have the agent review a `PLAN-<N>.md` file against the code and write a plain-English `REVIEW-<N>.md` next to it, then summarise it in the session under the same headings; `--lens` narrows the review, `--lens -` reads the lens from stdin; ask in the session and it applies suggestions to the plan and marks each one `**Applied:**` in the review (default model `opus`).
- `planner explore [--model <model>] <iteration-file>`: have the agent answer an `ITERATION-<N>.md` brief by exploring the code or data in rounds, asking you about anything unclear and checking in after each round so you can steer it or finish, and write a read-only `FINDINGS-<N>.md` next to it that opens with a summary and advisory recommendations, then summarise it in the session (default model `opus`).
- `planner summarise [--model <model>] [--brief <text>|-] <file>`: have the agent summarise a `PLAN-<N>.md`, `REVIEW-<N>.md` or `FINDINGS-<N>.md` file as the brief asks, in any format it can make (markdown, a sequence diagram, a slide deck, an animated GIF, an audio recording ...), referencing anything it uses from outside the file; the summary comes back in the session unless the brief asks for it on disk, when it is written once to `SUMMARY-<N>.<ext>`, or a `SUMMARY-<N>/` folder, next to the file; `--brief -` reads the brief from stdin, and with no brief you get a short markdown summary in the session (default model `opus`).
- `planner toc [--model <model>] <plan-folder>`: have the agent write `TABLE-OF-CONTENT.md` in a plan folder, replacing any existing one: a short summary of the work, then the files and folders grouped by number, each group with a one-line summary and, for plans, whether they are completed. Once it exists, `planner plan`, `explore`, `review`, `run` and `summarise` keep it up to date (default model `haiku`).
- `planner skills list`: list the skills planner ships.
- `planner skills install [--global] [--only <slug>,...]`: copy the skills into `.claude/skills`, or `~/.claude/skills` with `--global`; asks before replacing a skill that has changed.

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login
planner new --dir work/plans "Add login"  # => work/plans/202610271216-add-login
```

## Skills

These ship with planner and are installed with `planner skills install`.

- `commit-message`: makes the agent write commit messages in plain English, with a body that says what changed and why, an `Assisted-by:` trailer instead of `Co-Authored-By:`, and the usual subject and wrapping rules.
- `writing-erb`: makes the agent test a condition once in ERB templates, with `if`/`else` around the element and each branch holding the complete markup for that case, while a condition used only once stays inline.
- `writing-rspec`: makes the agent write spec descriptions that say what the code does, not how, in the present tense without "should", and use separate `expect` lines instead of `.and` matchers, and set up test objects with `let!` or `let` instead of in `before` blocks.
- `writing-rspec-controller-specs`: makes the agent write Rails controller and request specs with the request on the first line of each example, the response status checked first, and one example per request.

## Development

```sh
bundle exec rake  # specs, then RuboCop
```
