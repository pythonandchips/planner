When a user use `plan`, `review`, `run` and `summaries` they need to supply a file name.

I want to give the planner a folder only and for it to choose the highest number file as default.

For example if the folder `docs/plans/202601010101-something` contains

- ITERATION-001.md
- FINDINGS-001.md
- ITERATION-002.md
- PLAN-002.md
- REVIEW-002.md
- ITERATION-003.md

and I ran `planner plan docs/plans/202601010101-something` it would use the `ITERATION-003.md` file for the command.

`plan` will run only ITERATION files
`review` can run on the highest FINDINGS or PLAN file
`run` will run on the highest PLAN file
`summarise` will run on the highest PLAN or FINDINGS file

If a suitable file is not present it will throw an error


