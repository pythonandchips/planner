# planner

planner manages a four-step workflow for working with a coding agent. Start with `planner new <name>`, which creates a plan folder with an empty `ITERATION-001.md`, and write the task's brief in it. For each later iteration, `planner next <plan-folder>` creates the next empty `ITERATION-<NNN>.md`.

1. **Explore** (optional): an agent explores the codebase and gathers context for the task. `planner explore`
2. **Plan**: give the agent a specific task and shape the solution. `planner plan`
3. **Review** (optional): an agent reviews the plan and recommends improvements, optionally through a lens such as security or performance. `planner review`
4. **Run**: apply the plan to the codebase. `planner run`

## Install

```sh
git clone https://github.com/pythonandchips/planner.git
cd planner
bundle install && bundle exec rake install
```

## Usage

Run from the project root. A command that takes a file also takes a plan folder, and then uses the folder's latest file of the kinds it accepts.

### planner new

```sh
planner new [--dir <folder>] <given-name>
```

Creates a plan folder under `docs/plans/` with an empty `ITERATION-001.md` in it, and prints the file's path.

- `--dir <folder>`, `-d`: create the plan folder under this folder, relative to the project root.

```sh
planner new "Add login"  # => docs/plans/202610271216-add-login/ITERATION-001.md
planner new --dir work/plans "Add login"  # => work/plans/202610271216-add-login/ITERATION-001.md
```

### planner next

```sh
planner next <plan-folder>
```

Creates the next empty `ITERATION-<NNN>.md` in a plan folder, numbered one past the highest `ITERATION-NNN.md` there (or `001` when there is none), and prints the file's path.

```sh
planner next docs/plans/202610271216-add-login  # => docs/plans/202610271216-add-login/ITERATION-002.md
```

### planner explore

```sh
planner explore [--model <model>] [--deep] <iteration-file|plan-folder>
```

Has the agent answer an `ITERATION-<N>.md` brief by exploring the code or data in rounds, checking in with you after each, and write a read-only `FINDINGS-<N>.md` next to it.

- `--model <model>`, `-m`: default `opus`.
- `--deep`, `-d`: once you have clarified the brief and replied `Make it so`, the agent works on its own, researching and building spikes, and lists the spikes' branches in the findings. It first asks whether it can use git worktrees; if it cannot, it works on one local branch at a time in your checkout, hands work to at most one spike at a time, and pushes nothing.

### planner plan

```sh
planner plan <iteration-file|plan-folder>
```

Has the agent write the `PLAN-<N>.md` for an `ITERATION-<N>.md` next to it. It asks you about anything left open, including whether the plan should end in a commit.

### planner feedback

```sh
planner feedback <plan-folder> <pr>
```

Writes a pull request's open review comments to the next `ITERATION-<NNN>.md` in a plan folder, prints the file's path, then plans it as `planner plan` does. It needs the [GitHub CLI](https://cli.github.com) (`gh`) installed and logged in; `<pr>` is a number, URL or branch, as `gh pr view` takes it.

The file holds the unresolved inline threads that are not outdated, the review summaries and the conversation comments, each with its author, so the folder makes sense without GitHub. When there are none, it writes nothing.

### planner review

```sh
planner review [--model <model>] [--lens <text>|-] <file|plan-folder>
```

Has the agent review a `PLAN-<N>.md` or `FINDINGS-<N>.md` against the code and write `REVIEW-<N>.md` next to it. Ask in the session and it applies its suggestions to the plan.

- `--model <model>`, `-m`: default `opus`.
- `--lens <text>`, `-l`: narrow the review, for example to security or performance; `--lens -` reads it from stdin.

### planner run

```sh
planner run [--model <model>] [--print] <plan-file|plan-folder>
```

Has the agent implement a `PLAN-<N>.md` exactly, fixing failing verification steps or stopping to explain, then append deviations and stats to the plan. It commits only when the plan says to.

- `--model <model>`, `-m`: default `sonnet`.
- `--print`, `-p`: print the prompt, model and allowed tools as JSON instead, to run with your own `claude` command.

### planner summarise

```sh
planner summarise [--model <model>] [--brief <text>|-] <file|plan-folder>
```

Has the agent summarise a `PLAN-<N>.md`, `REVIEW-<N>.md` or `FINDINGS-<N>.md` in the format the brief asks for (markdown, a diagram, a slide deck ...). The summary comes back in the session, or is written to `SUMMARY-<N>.<ext>` next to the file when the brief asks for it on disk.

- `--model <model>`, `-m`: default `opus`.
- `--brief <text>`, `-b`: what to summarise and how; `--brief -` reads it from stdin. Without it you get a short markdown summary.

### planner toc

```sh
planner toc [--model <model>] <plan-folder>
```

Has the agent write `TABLE-OF-CONTENT.md` in a plan folder, replacing any existing one.

- `--model <model>`, `-m`: default `haiku`.

### planner skills

```sh
planner skills list
planner skills install [--global] [--only <slug>,...]
```

`list` lists the skills planner ships. `install` copies them into `.claude/skills`, asking before replacing a skill that has changed.

- `--global`: install into `~/.claude/skills` instead.
- `--only <slug>,...`: install only these skills.

## Skills

These ship with planner and are installed with `planner skills install`.

- `commit-message`: makes the agent write commit messages in plain English, with a body that says what changed and why, an `Assisted-by:` trailer instead of `Co-Authored-By:`, and the usual subject and wrapping rules.
- `writing-erb`: makes the agent test a condition once in ERB templates, with `if`/`else` around the element and each branch holding the complete markup for that case, while a condition used only once stays inline.
- `writing-rspec`: makes the agent write spec descriptions that say what the code does, not how, in the present tense without "should", and use separate `expect` lines instead of `.and` matchers, and set up test objects with `let!` or `let` instead of in `before` blocks.
- `writing-rspec-controller-specs`: makes the agent write Rails controller and request specs with the request on the first line of each example, the response status checked first, and one example per request.
- `writing-todos`: makes the agent add todo items for later work to `docs/TODO.md` or a plan folder's `TODO.md` in at most three plain sentences, citing the iteration, findings, plan or review file they came from, and remove them when the work is done.

## Development

```sh
bundle exec rake  # specs, then RuboCop
```

## Contributing

- Every pull request must include an iteration file and a plan file created with planner, in their plan folder under `docs/plans/`.
- Run `bundle exec rake` before opening it.
