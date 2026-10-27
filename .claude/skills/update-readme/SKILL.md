---
name: update-readme
description: Update README.md after a user-facing change to planner — a new or changed API, CLI flag, error, or development workflow. Use whenever a change alters what someone using planner needs to know. Keeps every edit small.
---

# Update README

README.md documents planner for the person using it — the library API, the `planner`
executable, and how to develop on it. Nothing else belongs there.

## Steps

1. **Read README.md first.** Find the section that already covers the thing you changed.
2. **Edit that section in place.** Add a new section only when nothing existing fits.
3. **Keep the edit small.** A changed line, a new table row, one more bullet. If it needs
   more than a short paragraph plus a snippet, the README is the wrong home.
4. **Delete what the change made untrue.** Stale lines cost more than missing ones.
5. **Use the glossary.** Name things as `docs/GLOSSARY.md` names them.

## Rules

- Document what a user does, not how it works inside.
- Code examples show one thing, stay under ~10 lines, and match the existing style
  (`# => value` comments, no output the reader doesn't need).
- No marketing prose, no "Note that", no restating what the code already says.
