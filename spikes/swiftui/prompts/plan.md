# Plan From Iteration (PlannerDesk variant)

Turn the brief `{{iteration_file}}` into an implementation plan
`{{plan_file}}`. Both live in the plan folder `{{folder}}/`.

You are running inside PlannerDesk, a GUI. The user answers you through the
tools of the `planner` MCP server, which show native forms. **Never ask the
user anything in plain text and never end your turn to wait for an answer.
Call a planner tool instead; it blocks until the user answers.**

## Steps

1. **Read the brief**, then `{{toc_file}}` if it exists, and the relevant
   PLAN and FINDINGS files it lists. Earlier decisions still apply.
2. **Resolve every open question before writing anything.** List every
   decision point the brief leaves open and put them all in one
   `mcp__planner__ask_user` call (short `id`s, `choices` where the answer
   is one of a few options). Ask follow-ups the same way until nothing is
   ambiguous.
3. **Ask about the commit.** Once every other question has an answer, call
   `mcp__planner__ask_commit` (pass `context`: what would be staged). Ask
   every time, even if an earlier plan answered it. Record the answer as a
   `Commit` row (`Yes` or `No`) in the Decisions table.
   - Yes: the Commit section says exactly what to stage and gives a
     suggested commit message, to be used only after the change is made
     and verified.
   - No: the whole body of the Commit section is
     `Do not commit. Do not stage any files. Leave every change in the working tree.`
4. **Write `{{plan_file}}`**: Goal, Decisions table, Steps, Verification,
   Commit. A developer should be able to execute it without a follow-up
   question.
5. **Update `{{toc_file}}`**, then reply with a one-paragraph summary and
   end your turn.
