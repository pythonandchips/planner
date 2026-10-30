# REVIEW-004 — docs/plans/202610291422-add-explore-task-to-planner/PLAN-004.md

## Lens

What a findings file and the agent's session reply would look like once PLAN-004 is applied, shown
as a worked example, and what that example shows about the plan.

## Summary

Applied to `lib/planner/prompts/explore.md.erb`, the plan's three replacements give the output
below. The file opens with a paragraph and then recommendations. The session reply is a header line,
the same paragraph and the recommendations. The plan's spec strings match that rendered text, and
its Verification expectations hold: `FINDINGS-004.md` does not exist yet, so the fake-agent run
ends with `opus` and `.../FINDINGS-004.md`. The main thing the example shows is that
`(finding <N>)` citations now have nothing near them saying what finding N is, in the file or in
the session.

### Example findings file

This is an illustration only. The brief is invented ("Which tools can the explore agent use, and
could it run read-only shell commands?"), but the evidence points at real lines in this repo. The
structure follows template lines 52-80 after replacement 1, plus the stats from lines 109-124.

````markdown
# FINDINGS-005 — Explore agent tools and read-only shell access

## Summary

The explore agent can use Read, Grep, Glob, Write and WebFetch, and may edit only its own
findings file without a prompt. It has no Bash tool, so it cannot run read-only shell commands
such as `git log`. Adding Bash would need a new entry in the tool list and an allow-list of
commands, because `--tools` and `--allowedTools` are the only controls planner passes to
`claude`. The review agent's setup is the closest pattern to copy.

## Recommendations

- Explore which `git` subcommands an `--allowedTools=Bash(git log:*)` style rule would need to cover before planning the change (finding 2)
- Plan a spec in `claude_spec.rb` that pins the exact `--tools` string so a widened tool list is a deliberate change (findings 1, 3)

## Questions

1. Which tools can the explore agent use?
2. Could it run read-only shell commands?

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Count WebFetch as in scope | Yes, the user confirmed it is part of the toolset |

## Findings

### 1. The tool list is fixed in the Claude agent

`EXPLORE_TOOLS = 'Read,Grep,Glob,Write,WebFetch'` (`lib/planner/agents/claude.rb:13`) is passed
as `--tools=` in `#explore` (`lib/planner/agents/claude.rb:32-35`).

### 2. There is no Bash tool and no command allow-list

The only pre-approved actions are `Edit(<findings file>)` and `WebFetch`
(`lib/planner/agents/claude.rb:34`).

### 3. The spec pins the arguments

`spec/planner/agents/claude_spec.rb:36-39` asserts the full argument list, including the
`--allowedTools` value.

---

## Stats

| Field | Value |
| --- | --- |
| Model | opus |
| Tokens | ~40k (estimate) |
````

There were no commands that needed help, so the "Commands that needed help" heading and table
are left out, as template line 126 says.

### Example session reply

Following replacement 3 (plan lines 74-87):

```
Findings written to `docs/plans/202610291422-add-explore-task-to-planner/FINDINGS-005.md`.

**Summary:** The explore agent can use Read, Grep, Glob, Write and WebFetch, and may edit only its own findings file without a prompt. It has no Bash tool, so it cannot run read-only shell commands such as `git log`. Adding Bash would need a new entry in the tool list and an allow-list of commands, because `--tools` and `--allowedTools` are the only controls planner passes to `claude`. The review agent's setup is the closest pattern to copy.

**Recommendations:**
- Explore which `git` subcommands an `--allowedTools=Bash(git log:*)` style rule would need to cover before planning the change (finding 2)
- Plan a spec in `claude_spec.rb` that pins the exact `--tools` string so a widened tool list is a deliberate change (findings 1, 3)
```

With no recommendations, the last block would read `**Recommendations:**` followed by `None.`.

For comparison, today's template (lines 134-144) would also print a `**Findings:**` block such as
`1. lib/planner/agents/claude.rb:13: The tool list is fixed in the Claude agent`, and the file's
Summary would carry the same numbered list (line 59).

## High-confidence findings

1. **Citations have nothing nearby to explain them.** In the example session reply,
   `(finding 2)` and `(findings 1, 3)` are the only references to findings, and the reply no
   longer says what finding 2 is. In the file, `## Recommendations` sits at template line 61,
   but the first `### 1.` heading is at line 77, after Questions and Decisions. A reader has to
   scroll past both sections or open the file to decode a citation. Before this plan, the
   numbered Summary list (line 59) and the session's `**Findings:**` list (lines 139-140)
   explained the citations. The plan keeps the citations on purpose (Decisions table, plan
   line 18), so this is a trade-off to confirm rather than a defect. The example makes it
   visible.

## Lower-confidence concerns

1. **"Word for word" is only implied in the prompt.** The Decisions table (plan line 17) says
   the session `**Summary:**` repeats the file's paragraph word for word. The text the agent sees
   (plan lines 78-86) says this only through the placeholder `<the Summary paragraph from the
   file>`. The note under the block covers recommendations ("worded as in the file") but not
   the summary. An agent could shorten the paragraph for the session. Prompt wording is a
   resolved decision (plan line 20), so this is noted, not proposed as a change.
2. **"A short paragraph" has no upper bound.** In the session the paragraph is printed on a
   single `**Summary:**` line, as in the example above. A five- or six-sentence paragraph turns
   into one long wrapped line in the terminal. The old "one or two sentences" kept it short.
   Whether that matters depends on how long agents make their paragraphs in practice.
3. **Verification never produces a real findings file or session reply.** Verification step 2
   (plan lines 143-155) checks the rendered prompt through a fake agent. Nothing in the plan
   runs `planner explore` for real, so the actual output (what this example approximates) is
   not seen before the commit. Running it would write a `FINDINGS-*.md` into the repo, so if
   it is done it should use a throwaway iteration file and the result should not be staged.

## Top recommendations

1. Confirm you are happy that `(finding <N>)` citations in the session reply and the file's
   Recommendations no longer have finding titles nearby (high-confidence finding 1).
2. Optionally, after the commit, run `planner explore` once on a throwaway brief to see a real
   findings file and session reply. Keep the output out of the commit.
