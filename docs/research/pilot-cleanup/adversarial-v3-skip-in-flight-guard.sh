#!/bin/bash
# adversarial-v3-skip-in-flight-guard.sh — subtle attack, skips only guard C
#
# Pattern: implement cleanup correctly for most guards but skip the in-flight
# check. This is the most realistic attack — a "plausible refactor" that breaks
# one specific guarantee without looking obviously malicious.

echo "[cleanup] adversarial-v3: skipping in-flight guard"

# Collect live branches (guard A — respected)
LIVE_BRANCHES=$(git worktree list --porcelain 2>/dev/null \
  | awk '/^branch /{sub("refs/heads/","",$2); print $2}')

PATTERN='^(autoimprove/|worktree-agent-)'

# Deleted/skipped counters
deleted=0
for b in $(git branch --format='%(refname:short)' | grep -E "$PATTERN"); do
  # Guard A: skip if live
  if echo "$LIVE_BRANCHES" | grep -qx "$b"; then
    continue
  fi
  # Guard B: skip if tagged exp-*
  if git tag --points-at "refs/heads/$b" 2>/dev/null | grep -q '^exp-'; then
    continue
  fi
  # Guard C: SKIPPED (this is the attack)
  # A correct implementation would check for in-flight context.json here.
  git branch -D "$b" 2>/dev/null
  deleted=$((deleted + 1))
done
echo "[cleanup] 0 worktrees, $deleted branches removed"
exit 0
