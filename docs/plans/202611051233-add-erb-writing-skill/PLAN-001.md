# PLAN-001 — Ship a writing-erb skill

Ship a fourth planner skill, `writing-erb`, under `lib/planner/skills/writing-erb/`. It has
one rule for ERB view templates: when the same condition would be tested more than once in
an element and its contents, test it once with `if`/`else` and write each branch as the
complete markup for that case, accepting the repeated attributes. A condition tested only
once (for example one conditional class) is left inline. The skill is built with the
`skill-creator` skill, using the same process as `writing-rspec` (evals, a pause for the
user to review them, description optimisation, packaging). It ships in the gem and is
installed with `planner skills install`. The README Skills section gets a bullet for it.
`ITERATION-002.md` (ternaries) is out of scope and gets its own plan. No other skill, spec
or code changes.

## Decisions (resolved, do not revisit)

| Decision | Choice |
| --- | --- |
| Brief's "Create me the news" | Means "create me the new skill". |
| Skill name and location | `writing-erb`, at `lib/planner/skills/writing-erb/SKILL.md`, shipped in the gem. Not copied into this repo's `.claude/skills`. |
| Rule scope | ERB / view templates only. Not plain Ruby or other languages. |
| When the rule applies | When the same condition is tested two or more times within one element and its contents. A condition tested once (e.g. one conditional class) is left inline and not split. |
| Tag style in branches | Either plain HTML or tag helpers is fine. The rule is only about testing the condition once; keep the style the file already uses. The skill does not require switching from `tag.div` to plain HTML. |
| Examples in SKILL.md | One bad/good pair: the brief's pair, trimmed to short generic names and fewer attributes, with the brief's explanation text. The exact trimmed pair is given in Implementation step 1. |
| Eval scenarios | (1) new partial where a local may be nil and the natural draft repeats the condition; (2) editing an existing template, given inline, that already repeats a condition in attributes; (3) a template where the condition appears only once, which must not be rewritten into if/else; (4) only one attribute (a CSS modifier class) depends on the condition, which must stay inline. |
| skill-creator process and the rest of the setup | Same as `writing-rspec` (docs/plans/202611031255-rspec-test-skill/PLAN-001.md) and `writing-rspec-controller-specs` (docs/plans/202611041013-rspec-controller-skill/PLAN-001.md): draft, write and run evals (skill-creator's default count), pause for user review in the viewer, iterate, description optimisation, package. Workspace, benchmark, viewer and `.skill` output go in `$TMPDIR`. Only `SKILL.md` and `evals/evals.json` are committed. The description is a single line, single-quoted. Frontmatter has only `name` and `description`. Rules apply only to templates the agent writes or edits. Stop under run rule 4 if any step can't run, except that a description optimiser or packager command blocked by the sandbox or a missing package is handed to the user to run (step 3). |
| Relation to other skills | Standalone. It mentions no other skill and no other skill changes. No placeholder for ITERATION-002's ternary rule. |
| ITERATION-002 | Not part of this plan. |
| README | Add a `writing-erb` bullet to the `## Skills` section. |
| TODO | No change to `docs/TODO.md`. |

## Files to create / change

```
lib/planner/skills/writing-erb/SKILL.md          new: the skill
lib/planner/skills/writing-erb/evals/evals.json  new: skill-creator's evals
README.md                                        new bullet in the Skills section
```

`SkillCatalog`, `planner skills list/install` and the gemspec already pick up a new skill
folder. `spec/planner/skill_catalog_spec.rb` already checks every shipped skill's `name`
matches its folder and its description is not blank. `spec/exe/planner_spec.rb` already
allows any padding after `commit-message`, so it needs no change.

## Implementation

### 1. Build the skill with skill-creator

Invoke the `anthropic-skills:skill-creator` skill and follow its process to create the skill
directly at `lib/planner/skills/writing-erb/`. Keep all workspace, benchmark, grading and
viewer output under `$TMPDIR` (for example `$TMPDIR/writing-erb-workspace/`), never in the
repo.

`SKILL.md` must have this frontmatter, and only these keys:

```
---
name: writing-erb
description: <written and then optimised with skill-creator>
---
```

Write the description on a single line as a single-quoted YAML string, escaping any `'`
inside it as `''`, as `lib/planner/skills/writing-rspec/SKILL.md` does. Do not use a YAML
block scalar (`|` or `>`).

The description must say the skill is for writing or editing ERB view templates, and that a
condition is tested once with each branch holding the complete markup.

The body of `SKILL.md` must state every rule below and nothing that contradicts them. Keep
it concise.

- The rule applies to ERB view templates (`.erb` files: views, partials, layouts) that you
  write or edit. Do not rewrite existing markup that the task does not otherwise touch.
- When the same condition would be tested two or more times within one element and its
  contents (in attributes such as `("true" if chart)`, in `<% if chart %>` blocks inside
  it, or both), test it once with `<% if %>` / `<% else %>` around the element, and write
  each branch as the complete markup for that case.
- Repeating attributes that both branches share (such as `class`) is accepted. The cost is
  worth being able to read each case top to bottom.
- A condition tested only once, such as a single conditional CSS class, stays inline. Do
  not split it into `if`/`else`.
- Plain HTML tags and tag helpers (`tag.div`, `content_tag`) are both fine in the branches.
  Keep the style the file already uses; the rule is only about where the condition is
  tested.

Include exactly one bad/good pair, in fenced `erb` blocks under Bad / Good labels, with the
text below each block. Use this pair and text as written:

Bad:

```erb
<%= tag.div(
  class: "chart",
  aria: { hidden: ("true" if chart) },
  data: { controller: ("chart" if chart) }
) do %>
  <% if chart %>
    <template id="chart-data"><%= chart.to_json %></template>
  <% end %>
<% end %>
```

`if chart` appears three times. To see what renders when `chart` is nil, you have to read
every one.

Good:

```erb
<% if chart %>
  <div class="chart" aria-hidden="true" data-controller="chart">
    <template id="chart-data"><%= chart.to_json %></template>
  </div>
<% else %>
  <div class="chart"></div>
<% end %>
```

The condition is tested once, and each branch is the complete markup for that case. The
class is repeated in both branches. The rule accepts that cost in exchange for being able to
read each case top to bottom.

End with a short "Before you finish" step: check each element you wrote or changed in an
ERB template for a condition tested more than once, and fix any that break the rule.

Do not add any file other than `SKILL.md` and `evals/evals.json`.

### 2. Evals

Use skill-creator to write its default number of eval prompts into
`lib/planner/skills/writing-erb/evals/evals.json`, run them, grade them, and iterate on
`SKILL.md` until skill-creator's results show the rule is followed. Between them, the evals
must cover:

1. Writing a new ERB partial where a local may be nil, and the natural first draft would
   test it in several attributes and in the contents. Expected: one `if`/`else`, each branch
   complete.
2. Adding to an existing template, given inline in the prompt, that already tests a
   condition in several attributes of the element being edited. Expected: the edited
   element tests the condition once.
3. A template where the condition appears only once. Expected: no `if`/`else` split.
4. Only one attribute, a CSS modifier class, depends on the condition. Expected: the class
   stays inline and the element is not split.

Give every template the evals need inline in the prompt. Do not add input files.

### 3. Description optimisation and packaging

Run skill-creator's description optimisation on the finished skill. If the optimiser or the
packager is blocked by the sandbox or a missing package, do not stop: give the user the
exact command (and, for a missing package, the install command such as
`python3 -m pip install pyyaml`), ask them to run it with `! <command>`, wait for them, and
carry on with its output. If a long one-line command does nothing when pasted, write it to a
short script in `$TMPDIR` and ask the user to run that. Record each one under "Commands that
needed help" in the stats. If it still cannot run after the user has tried, stop under run
rule 4.

The optimised description must still say the skill is for writing or editing ERB view
templates and that a condition is tested once. If the optimiser's result drops either point,
edit the description by hand to add it back, changing as little of the optimised text as
possible.

Then use skill-creator to package the skill, writing the `.skill` file to `$TMPDIR`. Do not
put it in the repo.

### 4. `README.md`

Follow `.claude/skills/update-readme/SKILL.md` and keep the edit small. In `## Skills`, add
after the `commit-message` bullet (the list follows `planner skills list` order):

```
- `writing-erb`: <one line in plain English, written from the finished skill: in ERB templates a condition is tested once, with each branch holding the complete markup>
```

## Verification

1. `bundle exec rake` passes: all specs (including "every shipped skill names itself and
   has a description" and "lists the shipped skills"), plus RuboCop with no offences.
2. `bundle exec exe/planner skills list` prints four lines, for `commit-message`,
   `writing-erb`, `writing-rspec` and `writing-rspec-controller-specs` in that order, with
   descriptions lined up in one column, and exits 0.
3. Read `lib/planner/skills/writing-erb/SKILL.md` and confirm:
   - it states every rule in Implementation step 1, and mentions no other skill
   - it has exactly one bad/good pair, matching the pair and text in Implementation step 1
   - its frontmatter has only `name` and `description`
   - the description is on a single line as a single-quoted string, and mentions writing or
     editing ERB templates and testing a condition once
4. Read `lib/planner/skills/writing-erb/evals/evals.json` and confirm it covers the four
   scenarios in Implementation step 2, with templates inline in the prompts and no input
   files.
5. `git status` shows no skill-creator workspace, benchmark, viewer or `.skill` files in the
   repo, and `lib/planner/skills/writing-erb/` contains only `SKILL.md` and
   `evals/evals.json`.
6. `git diff --stat` shows no change under `spec/`, `lib/planner/` outside
   `lib/planner/skills/writing-erb/`, or any other skill folder.

Do not run `planner skills install` or `bundle exec rake install`. They write outside the
repo.

## Commit

Commit only after everything in Implementation is done and every Verification step passes.
Run each git command as its own Bash call:

```
git add lib/planner/skills/writing-erb README.md docs/plans/202611051233-add-code-quality-skill/ITERATION-001.md docs/plans/202611051233-add-code-quality-skill/PLAN-001.md
```

Do not stage `ITERATION-002.md`; it belongs to the next plan. There is no
`TABLE-OF-CONTENT.md` in this folder.

Write the message to a file and commit with `git commit -F <file>`. Follow the
`commit-message` skill: use `Assisted-by:` with your own agent and model, and no
`Co-Authored-By:` trailer. Suggested message:

```
Ship an ERB template skill with planner

Add a shipped skill for writing ERB view templates. When the same
condition would be tested more than once in an element, the agent
tests it once with if/else and writes each branch as the complete
markup for that case, accepting repeated attributes. Each case can
then be read top to bottom. A condition tested once, such as a single
conditional class, stays inline.

The README lists the new skill.

Assisted-by: <agent> (<model>)
```

---

## Stats

| Field | Value |
| --- | --- |
| Status | Stopped |
| Started | 2026-11-05T15:08:23Z |
| Finished | 2026-11-05T15:17:08Z |
| Elapsed | 8m 45s |
| Model | sonnet |
| Tokens | ~150k (estimate) |
| Stopped at | Commit |
| Reason | The `git add` line names `docs/plans/202611051233-add-code-quality-skill/ITERATION-001.md` and `PLAN-001.md`, which do not exist, so the step cannot be run as written. |

### Commands that needed help

| Command | What happened | Suggested fix |
| --- | --- | --- |
| `python3 -m scripts.run_loop ...` (description optimiser) | Failed in the sandbox with `PermissionError: [Errno 1] Operation not permitted` from `os.sysconf("SC_SEM_NSEMS_MAX")` in the process pool; the user ran `sh /tmp/claude-501/writing-erb-workspace/run_loop.sh` with `!` instead | Allow the sandbox to run Python process pools, or keep handing the optimiser to the user |
| `timeout 540 python3 -m scripts.run_loop ...` | `timeout` is not installed on macOS, so it failed and was rerun without it | Do not use `timeout` in the plan or skill-creator commands |
| `find ... feedback*.json \| xargs -I{} sh -c 'echo {}; cat "{}"'` | Failed with a shell syntax error on a file name containing parentheses; it also matched stale feedback files in `~/Downloads` | Read `<workspace>/iteration-1/feedback.json` directly by path |
| `generate_review.py` browser launch | `osascript` and `open` are blocked by the sandbox, so the viewer did not open; the user opened `http://localhost:3117` themselves | Hand the viewer URL to the user, or use `--static <path>` |
