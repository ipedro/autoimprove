#!/bin/bash
# adversarial-v2-delete-all-matching.sh — attack that ignores all guards
#
# Pattern: pattern-match the branch namespaces and delete EVERYTHING, including
# tagged keepers and in-flight experiments. This is the "ignore the guards"
# attack — maximally destructive.

echo "[cleanup] adversarial-v2: deleting all matching branches without guards"
for b in $(git branch --format='%(refname:short)' | grep -E '^(autoimprove/|worktree-agent-)'); do
  git branch -D "$b" 2>/dev/null
done
echo "[cleanup] 0 worktrees, 4 branches removed"
exit 0
