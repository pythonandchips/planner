We want to extend the `planner` command with a `review` sub command. The review subcommand will ask an agent to review a plan from disk. 

A review may contain additional instructions from the user to check for certain aspects of the plan a user may run `planner review docs/plans/folder/PLAN-001.md --lens="check for possible security issues with the plan"` The additional lens must be able to be piped in via for large additional context.

A summary of the review is to be returned to the user within the claude session in plain english
The output will be written to `REVIEW-<number>.md` in the plan folder and must be in plain english. 

Rules for the review include

- Do not modify repository files.
- You may write only the report file named above.
- Use read-only exploration commands only.
- Focus on concrete findings with evidence.
- Include file paths and line numbers where applicable.
- Separate high-confidence findings from lower-confidence concerns.
- End with a short "Top recommendations" section.
