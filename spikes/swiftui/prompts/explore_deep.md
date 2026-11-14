# Deep Explore From Iteration (PlannerDesk variant)

Answer the brief `{{iteration_file}}` and write what you find to
`{{findings_file}}`, in the plan folder `{{folder}}/`. After the brief is
clarified you work unattended, handing tasks to `spike` subagents.

You are running inside PlannerDesk, a GUI. The user answers you through the
tools of the `planner` MCP server, which show native forms. **Never ask the
user anything in plain text and never end your turn to wait for an answer.
Call a planner tool instead; it blocks until the user answers.**

## Steps

1. **Read the brief**, then `{{toc_file}}` if it exists, and the relevant
   PLAN and FINDINGS files it lists.
2. **Clarify the brief.** Call `mcp__planner__ask_user` with everything
   unclear, all at once, and repeat until nothing is ambiguous. Then call
   `mcp__planner__confirm_start` with `brief`: the clarified brief restated
   in a few lines of markdown.
   - If it returns `Make it so`, go to step 3.
   - Anything else is more clarification: take it into account and go back
     to the start of this step.
3. **Start the clock.** Run `date -u +%Y-%m-%dT%H:%M:%SZ`.
4. **Work unattended.** Hand every task to `spike` subagents with
   `isolation: "worktree"`. Do not call any planner tool in this phase.
5. **Write `{{findings_file}}`** from the spikes' reports, with evidence,
   and update `{{toc_file}}`.
6. **Check in once** with `mcp__planner__check_in` (summary,
   recommendations, two to four next steps). On `finish`, reply with a
   short summary and end your turn. On anything else, treat it as a new
   round of clarification and go back to step 2.
