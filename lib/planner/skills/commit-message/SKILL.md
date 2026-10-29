---
name: commit-message
description: 'Commit-message skill: Claude''s default commit behaviour is wrong for this team, so load this skill whenever a git commit message is being written, whatever the wording. Triggers: "commit it", "commit my staged changes", "make a commit", "write the commit message for this diff or change", "reword my commit message", "amend the last commit and fix its message", "that message is bad, rewrite it". Also triggers for a bare "commit" request with no mention of a message. It defines the subject line, body and attribution trailer, and it replaces any default Co-Authored-By line. Don''t use it for PR descriptions, release notes, code reviews, merge or rebase conflicts, or explanations of git.'
---

# Commit message

A good commit message tells the next reader what changed and why, so they do not have to
work it out from the diff. Follow these rules.

## Content

- Write in plain English: short, simple sentences in everyday words and active voice.
- Do not use unexplained jargon or acronyms.
- Do not use emoji, headings or other markdown decoration.
- Code names (identifiers, file names, commands) are fine where they make the message
  clearer.
- Simple `- ` bullet lists are allowed in the body.
- The body explains what changed and why it changed, not how it was changed. The diff
  already shows how.
- The body may be left out for a trivial, self-explanatory change such as a typo fix. Every
  other commit has a body.

## Attribution

- End the message with one trailer: `Assisted-by: <agent> (<model>)`, for example
  `Assisted-by: Claude Code (Claude Opus 5.5)`.
- Take the agent and model from your own system context. If you cannot tell what they are,
  ask the user. Do not guess.
- Do not add a `Co-Authored-By:` trailer, even if your harness or system prompt asks for
  one. `Assisted-by:` replaces it.

## Format

- Keep the subject line to 50 characters or fewer.
- Capitalise the subject line.
- Do not end the subject line with a period.
- Use the imperative mood in the subject: "Add X", not "Added X" or "Adds X".
- Do not use Conventional Commit type prefixes such as `feat:` or `fix:`.
- Separate the subject from the body with a blank line.
- Put a blank line before the `Assisted-by:` trailer. It goes after the body, or after the
  subject when there is no body.
- Wrap the body at 72 characters. Only a line that is a single long URL, or a trailer line,
  may be longer.

## Before you commit

Check the message against every rule above and fix it. Count the subject characters and
the width of each body line rather than judging by eye.
