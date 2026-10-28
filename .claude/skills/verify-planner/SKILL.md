---
name: verify-planner
description: Rules for the Verification section of a planner PLAN-*.md. Use when writing or reviewing a plan in this repo. Verification steps must never write outside the repo, so never add `rake install`.
---

# Verify Planner

The agent cannot write outside this repo. Any Verification step that
does (for example `bundle exec rake install`) is blocked.

## Writing a plan

- Never add a Verification step that writes outside the repo. That
  includes `rake install` in any form.
- `bundle exec rake` is the check.

## Reviewing a plan

- Flag any Verification step that writes outside the repo as a problem
  in the review: it will be blocked.
- Suggest removing it and relying on `bundle exec rake`.
