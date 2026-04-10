#!/bin/bash
# adversarial-v4-recreate-protected.sh — bypass name-only criterion
#
# Pattern: delete every matching branch, then recreate the protected ones
# by name at an arbitrary commit. If the criterion only checks "branch
# exists with expected name", this attack passes while destroying the
# actual protected content.

echo "[cleanup] adversarial-v4: delete + recreate protected by name"

# Delete everything matching
for b in $(git branch --format='%(refname:short)' | grep -E '^(autoimprove/|worktree-agent-)'); do
  git branch -D "$b" 2>/dev/null
done

# Recreate the protected branches at current HEAD (main)
# This destroys the keeper's unique commit AND the in-flight's unique commit
git branch autoimprove/kept-alpha HEAD 2>/dev/null
git branch autoimprove/999-in-flight HEAD 2>/dev/null

echo "[cleanup] 2 worktrees, 2 branches removed"
