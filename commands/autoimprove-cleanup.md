---
name: autoimprove-cleanup
description: Manually sweep stale autoimprove worktrees and branches. Safe to run anytime — protects live worktrees, tagged keepers, and in-flight experiments.
argument-hint: "[--dry-run] [--verbose]"
---

Invoke the `autoimprove:cleanup` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Arguments

| Argument | Description |
|----------|-------------|
| `--dry-run` | Print what would be removed without touching anything. Use this first. |
| `--verbose` | Show per-candidate skip reasons (live worktree, tagged, in-flight). |

## Usage Examples

```
# Preview first — recommended before any destructive run
/autoimprove cleanup --dry-run

# Preview with per-branch reasoning
/autoimprove cleanup --dry-run --verbose

# Destructive sweep
/autoimprove cleanup
```

## What It Does

Invokes `scripts/cleanup-worktrees.sh`, which:

1. Lists all worktrees and branches matching `autoimprove/*` or `worktree-agent-*`.
2. Skips anything that is currently checked out in a live worktree.
3. Skips anything tagged `exp-*` (kept experiments — never delete).
4. Skips anything whose branch name embeds an experiment id with no terminal verdict in `experiments/*/context.json` (in-flight work).
5. Force-removes the remaining worktrees and deletes their branches.
6. Runs `git worktree prune` to clear stale admin files.

Exits 0 always. Prints a summary line `[cleanup] N worktrees, M branches removed`.

## When to Use

- After a Claude Code crash left orphan `worktree-agent-*` branches behind.
- Before a release, to tidy the branch list.
- Whenever `git branch` looks noisy.
- Not normally needed — `/autoimprove run` already calls cleanup at session end (step 4b-ii) and session start (step 2f-ii).

## Safety

The script is designed to be safe to run even while another autoimprove session is mid-experiment:

- The live-worktree guard prevents deletion of any branch that still has a checked-out worktree.
- The `exp-*` tag guard protects every kept experiment.
- The in-flight guard protects experiments whose `context.json` has no verdict yet.

If you are unsure, always run `--dry-run --verbose` first.

## Related Commands

- `/autoimprove run` — main experiment loop (calls cleanup automatically)
- `/autoimprove report` — session history review
