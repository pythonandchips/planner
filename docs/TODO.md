# TODO

- `planner plan --model <model>`: the plan model is hardcoded to opus.
- `--help`/`-h` (top level and per subcommand) should print usage and exit 0.
- Find the project root from the git top-level instead of cwd.
- Add rules for run with commit discipline around content of commit message and PR body
- Ship more skills under `lib/planner/skills` (for example running yarn commands).
- Allow the review fill to be commited even when it is not part of the plan
- limit the plan and review to only read the files in the same folder. Not files in other `docs/plans`
- Have plan ignore files that are gitignored for staging
- revert iteration, undo the last iteration removing commits and any plan, findings or review files and update Table of content
- Add a command for planner to launch a markdown reader. Possibly a web page
- Change the plan to make the commit message an example not a specification. Allow the runner to invoke the command and write the message
- Rewrite the content of `README.md` in full so it is accurate and consistent, rather than patching it one bullet at a time. From [PLAN-001.md](plans/202611181357-run-latest-file/PLAN-001.md).
- refactor the commands so they take a model rather than args. This can then also be used to find the file so the commands don't need to
- add a command that sets the current folder for planner so that when you run `plan`, `review` etc it defaults to the set folder
- Add a github url to a file which will mean the todo's and contexts can be kept on a card. There could be multiple cards per folder so need to think more on how that will sync
- [Skill] No comments unless appoved by me
- Ensure all files output a estimate token usage
- Add an option for creating output as html. This will require explore, plan, review, summarise and toc to be able to ingest html
- Add a review with judges command that will use `pi` to produce 3 review files. once the files are created have claude opus combine and provide updates. 

## Advised TODO.
This list comes from a review of work done with the planner command.

- Make `planner plan`, `planner explore` and `planner run` refuse an empty `ITERATION-<N>.md` or `PLAN-<N>.md`. When given a folder they pick the highest number, so a stray empty file such as `ITERATION-15.md` gets planned from nothing.
- Add a `planner next <plan-folder>` command that creates the next zero-padded `ITERATION-<NNN>.md` from a brief template. Iteration files after the first are made by hand today, which led to names like `ITERATION-15.md`.
- Give the brief template the headings Context, Ask, Done when, Out of scope and Commits. Briefs without "Done when" and "Out of scope" led to choices that later iterations reversed, such as a rounded y axis and a hidden crosshair.
- Add the plan folder's context to the plan and explore prompts, so briefs no longer need to open with a copied "we are working on … see FINDINGS-001.md" paragraph.
- Use "stage" rather than "iteration" for the delivery steps that findings propose. Briefs said "iteration 3 from the findings file", which is easy to confuse with the `ITERATION-<N>.md` files.
- Let the plan review read the folder's findings and earlier Decisions tables, and check that the plan does not drift from them. A plan review missed that a plan went against a findings recommendation, and the PR review had to send it back.
- Keep a `DECISIONS.md` in each plan folder, or a decisions section in `TABLE-OF-CONTENT.md`, that lists the decisions still in force and notes which plan replaced each one. Today plans say "decisions from PLAN-002 to PLAN-013 still apply, except …", so you have to read every plan to know what stands.
- Let the plan agent make small mechanical choices, or ones the repo's conventions already settle, and list them as "Assumed" rows the user can override. The rule against making any decision fills Decisions tables with rows like "remove the blank line".
- Tell the plan agent to check the expected values it writes into specs, for example with a quick script, or to describe the behaviour and let the run agent fill in the values. Literal expected values written by hand were the most common error that reviews found.
- Have the plan agent suggest a skill or `CLAUDE.md` change when PR feedback corrects a repo convention. Tests that read the Unovis config were added in three plans and then deleted in a fourth, because nothing recorded the convention.
- Pull PR review comments into the iteration file or plan when a brief points at a pull request, for example with a `planner feedback <pr>` command. The folder should make sense without GitHub.
- Check with `git check-ignore` whether the plan folder is ignored, and render the plan and run prompts to match. When `docs/` is ignored, every plan explains this while the run prompt still says to stage the plan file and the table of contents.
- Record real token usage and elapsed time in the stats instead of the agent's estimate, for example from Claude Code's JSON output or the session transcript. Most plans report "~60k (estimate)", and some elapsed times are too short to be true.
- Add a "Skipped verification" row to the run stats for steps the user chose to skip. Plans recorded skipped rubocop and stylelint steps as free text outside the template.
- Make commit attribution consistent across plan, review and run. Commits show a mix of `Assisted-by:` without the stage, `Co-Authored-By:` and both, because Claude Code's own attribution instruction and the repo's `commit-message` skill compete with the planner prompts.
- Tell the plan agent to name the skill that runs a command, such as `running-yarn`, rather than copying the command into the plan. A plan hard-coded `private/bin/yarn` after the skill had changed to `bin/agent-yarn`.

- No source links: the items came from this review, not from a file in a planner plan folder, so I left them off. If you copy them into a plan folder there, add From [...] links as you go.
- Not checked for duplicates: I haven't seen the planner repo's existing docs/TODO.md, so remove any items it already covers.
- Brief-writing habits left out: fixing typos in identifiers and copying names from the code are about how briefs are written, not changes to planner, so they aren't on the list.
