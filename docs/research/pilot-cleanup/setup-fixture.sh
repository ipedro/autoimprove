#!/bin/bash
# setup-fixture.sh — create a fixture temp repo and print its path + SHAs
#
# Unlike fixture.sh (which runs an impl inline), this script only SETS UP
# the temp repo and prints the SHAs as an export-able shell snippet. The
# caller runs the implementation (possibly via a Claude subagent) and then
# runs check.sh with the exported env vars.
#
# Usage:
#   eval $(docs/research/pilot-cleanup/setup-fixture.sh)
#   # ... run implementation in $PILOT_TMP ...
#   bash docs/research/pilot-cleanup/check.sh  # uses exported env vars
#   rm -rf "$PILOT_TMP"
#
# Output: shell `export` statements on stdout, one per env var.

set -uo pipefail

TMP=$(mktemp -d)

cd "$TMP" || { echo "echo 'setup failed to cd' >&2; exit 2"; exit 2; }

git init -q -b main 2>/dev/null || git init -q 2>/dev/null
git config user.email "pilot@fixture.local"
git config user.name "pilot"
echo "seed" > README.md
git add README.md
git commit -q -m "seed"

# Tagged keeper with unique commit
git checkout -q -b autoimprove/kept-alpha
echo "kept work" > kept.txt
git add kept.txt
git commit -q -m "kept experiment work"
git tag exp-alpha HEAD
git checkout -q main

# Orphan 1 (autoimprove/*) with unique commit
git checkout -q -b autoimprove/orphan-1
echo "orphan 1" > orphan1.txt
git add orphan1.txt
git commit -q -m "orphan 1 work"
git checkout -q main

# Orphan 2 (worktree-agent-*) with unique commit
git checkout -q -b worktree-agent-orphan-2
echo "orphan 2" > orphan2.txt
git add orphan2.txt
git commit -q -m "orphan 2 work"
git checkout -q main

# In-flight experiment with unique commit
git checkout -q -b autoimprove/999-in-flight
echo "in-flight work" > inflight.txt
git add inflight.txt
git commit -q -m "in-flight work"
git checkout -q main

# Context.json on main — marks experiment 999 as in-flight (verdict:null)
mkdir -p experiments/999
cat > experiments/999/context.json <<'EOF'
{
  "id": "999",
  "theme": "pilot",
  "verdict": null,
  "baseline_sha": null
}
EOF
git add experiments
git commit -q -m "add in-flight context"

# Emit export statements for the caller
cat <<EOF
export PILOT_TMP="$TMP"
export PILOT_SHA_KEPT_ALPHA="$(git rev-parse autoimprove/kept-alpha)"
export PILOT_SHA_IN_FLIGHT="$(git rev-parse autoimprove/999-in-flight)"
export PILOT_SHA_EXP_ALPHA_TAG="$(git rev-parse exp-alpha)"
export PILOT_SHA_MAIN="$(git rev-parse main)"
export PILOT_HASH_CONTEXT="$(git hash-object experiments/999/context.json)"
EOF
