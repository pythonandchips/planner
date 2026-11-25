We cannot always use worktrees for `plan explore --deep` so we need to loosen the rules on it a bit.

Ask first if it can use worktrees

If it cannot use worktrees do the following
Allow it to modify files on a branch only.
Allow it to run bash command so it can for example run spikes
Allow a single spike agent to run at a time if required to reduce context size

