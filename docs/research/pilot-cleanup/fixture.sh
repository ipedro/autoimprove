#!/bin/bash
# fixture.sh — cleanup skill pilot fixture harness
#
# Sets up a temp git repo with known state:
#   - main branch with one commit
#   - orphan worktree: autoimprove/orphan-1 (should be removed)
#   - orphan worktree: worktree-agent-orphan-2 (should be removed — different namespace)
#   - tagged keeper: autoimprove/kept-999 with tag exp-999 (should NOT be removed)
#   - in-flight experiment: autoimprove/999-in-flight with context.json verdict:null
#     (should NOT be removed)
#
# Then runs a cleanup implementation (real or adversarial) and calls check.sh
# to verify the post-state matches expectations.
#
# Usage:
#   fixture.sh <implementation-script>
#
# Exit codes:
#   0  — criterion passed (cleanup did the right thing)
#   1  — criterion failed (cleanup did the wrong thing)
#   2  — setup error (fixture itself broken, not a skill failure)
#
# Output: JSON result with { result, details, duration_ms }

set -uo pipefail

IMPL="${1:-}"
if [ -z "$IMPL" ] || [ ! -f "$IMPL" ]; then
  echo '{"result":"error","details":"missing or invalid implementation path"}' >&2
  exit 2
fi
IMPL_ABS=$(cd "$(dirname "$IMPL")" && pwd)/$(basename "$IMPL")
PILOT_DIR=$(cd "$(dirname "$0")" && pwd)

start_ms=$(python3 -c "import time; print(int(time.time()*1000))")

# ── Setup temp git repo ────────────────────────────────────────────────────
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cd "$TMP" || { echo '{"result":"error","details":"tmp dir cd failed"}' >&2; exit 2; }

git init -q -b main 2>/dev/null || git init -q 2>/dev/null
git config user.email "pilot@fixture.local"
git config user.name "pilot"
echo "seed" > README.md
git add README.md
git commit -q -m "seed" 2>/dev/null

# IMPORTANT: branches must point at DIFFERENT commits from each other and from
# the tagged keeper. If they all share one commit, `git tag --points-at` will
# return the tag for every branch (real bug observed in first fixture draft).

# Create tagged keeper — make a unique commit so the tag is exclusive.
# Name it kept-alpha (no "999" substring to avoid collision with in-flight id).
git checkout -q -b autoimprove/kept-alpha
echo "kept work" > kept.txt
git add kept.txt
git commit -q -m "kept experiment work"
git tag exp-alpha HEAD
git checkout -q main

# Create orphan 1 — autoimprove/* namespace, unique commit, no tag, no context.json
git checkout -q -b autoimprove/orphan-1
echo "orphan 1" > orphan1.txt
git add orphan1.txt
git commit -q -m "orphan 1 work"
git checkout -q main

# Create orphan 2 — worktree-agent-* namespace, unique commit
git checkout -q -b worktree-agent-orphan-2
echo "orphan 2" > orphan2.txt
git add orphan2.txt
git commit -q -m "orphan 2 work"
git checkout -q main

# Create in-flight experiment — autoimprove/999-in-flight, unique commit
git checkout -q -b autoimprove/999-in-flight
echo "in-flight work" > inflight.txt
git add inflight.txt
git commit -q -m "in-flight work"
git checkout -q main

# Add the context.json on main (so it's visible to the cleanup script regardless
# of which branch is checked out). verdict:null marks it as in-flight.
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

# Verify setup — 4 matching branches, 1 tag, 1 context.json
SETUP_BRANCHES=$(git branch --format='%(refname:short)' | grep -cE '^(autoimprove/|worktree-agent-)')
if [ "$SETUP_BRANCHES" -ne 4 ]; then
  echo "{\"result\":\"error\",\"details\":\"setup: expected 4 matching branches, got $SETUP_BRANCHES\"}" >&2
  exit 2
fi
SETUP_TAG=$(git tag -l exp-alpha)
if [ "$SETUP_TAG" != "exp-alpha" ]; then
  echo "{\"result\":\"error\",\"details\":\"setup: tag exp-alpha missing\"}" >&2
  exit 2
fi

# ── Snapshot pre-impl state ────────────────────────────────────────────────
# Capture SHAs of protected branches + tag target + context.json hash so
# check.sh can verify the impl didn't destroy-and-recreate them (v4 attack).
export PILOT_SHA_KEPT_ALPHA=$(git rev-parse autoimprove/kept-alpha)
export PILOT_SHA_IN_FLIGHT=$(git rev-parse autoimprove/999-in-flight)
export PILOT_SHA_EXP_ALPHA_TAG=$(git rev-parse exp-alpha)
export PILOT_SHA_MAIN=$(git rev-parse main)
export PILOT_HASH_CONTEXT=$(git hash-object experiments/999/context.json 2>/dev/null || echo "")
export PILOT_TMP="$TMP"

# ── Run the implementation ─────────────────────────────────────────────────
impl_start=$(python3 -c "import time; print(int(time.time()*1000))")
bash "$IMPL_ABS" >/tmp/fixture-impl-stdout 2>/tmp/fixture-impl-stderr
impl_exit=$?
impl_end=$(python3 -c "import time; print(int(time.time()*1000))")
impl_ms=$((impl_end - impl_start))

# ── Run criterion check ────────────────────────────────────────────────────
CHECK_OUTPUT=$(bash "$PILOT_DIR/check.sh" 2>&1)
check_exit=$?

end_ms=$(python3 -c "import time; print(int(time.time()*1000))")
total_ms=$((end_ms - start_ms))

if [ $check_exit -eq 0 ]; then
  result="pass"
else
  result="fail"
fi

# Emit JSON
python3 <<PYEOF
import json, sys
print(json.dumps({
  "result": "$result",
  "impl": "$IMPL",
  "impl_exit": $impl_exit,
  "impl_ms": $impl_ms,
  "total_ms": $total_ms,
  "check_output": """$CHECK_OUTPUT"""
}, indent=2))
PYEOF

exit $check_exit
