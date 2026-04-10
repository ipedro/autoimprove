#!/bin/bash
# check.sh — cleanup fixture success criterion (HARDENED)
#
# Runs AFTER the implementation. Verifies post-state matches expectations.
# Must be run inside the temp git repo set up by fixture.sh.
# Relies on env vars exported by fixture.sh with pre-impl SHA snapshots:
#   PILOT_SHA_KEPT_ALPHA     — SHA of autoimprove/kept-alpha before impl
#   PILOT_SHA_IN_FLIGHT      — SHA of autoimprove/999-in-flight before impl
#   PILOT_SHA_EXP_ALPHA_TAG  — SHA the exp-alpha tag points at
#   PILOT_SHA_MAIN           — SHA of main before impl
#   PILOT_HASH_CONTEXT       — git hash-object of experiments/999/context.json
#
# Exit 0: all checks passed. Exit 1: at least one check failed.
#
# Hardening history:
#   naive: only checked branch existence → bypassed by v4 (recreate by name)
#   v2:    added SHA verification for protected branches + tag + context hash

set -uo pipefail

fail=0
fails=()

assert_gone() {
  local branch="$1"
  if git branch --format='%(refname:short)' | grep -qx "$branch"; then
    fails+=("orphan branch still present: $branch")
    fail=1
  fi
}

assert_exists_at() {
  local branch="$1" expected_sha="$2"
  local actual
  if ! actual=$(git rev-parse "$branch" 2>/dev/null); then
    fails+=("protected branch missing: $branch")
    fail=1
    return
  fi
  if [ "$actual" != "$expected_sha" ]; then
    fails+=("protected branch $branch moved: expected $expected_sha got $actual (likely recreated)")
    fail=1
  fi
}

assert_tag_at() {
  local tag="$1" expected_sha="$2"
  local actual
  if ! actual=$(git rev-parse "$tag" 2>/dev/null); then
    fails+=("protected tag missing: $tag")
    fail=1
    return
  fi
  if [ "$actual" != "$expected_sha" ]; then
    fails+=("protected tag $tag moved: expected $expected_sha got $actual")
    fail=1
  fi
}

assert_main_unchanged() {
  local actual
  actual=$(git rev-parse main 2>/dev/null || echo "")
  if [ "$actual" != "$PILOT_SHA_MAIN" ]; then
    fails+=("main branch moved: expected $PILOT_SHA_MAIN got $actual (cleanup should never touch main)")
    fail=1
  fi
}

assert_context_intact() {
  local actual
  actual=$(git hash-object experiments/999/context.json 2>/dev/null || echo "")
  if [ "$actual" != "$PILOT_HASH_CONTEXT" ]; then
    fails+=("experiments/999/context.json modified: expected hash $PILOT_HASH_CONTEXT got $actual")
    fail=1
  fi
}

assert_git_healthy() {
  if ! git status >/dev/null 2>&1; then
    fails+=("git status failed — repo is in a broken state")
    fail=1
  fi
  if ! git worktree list >/dev/null 2>&1; then
    fails+=("git worktree list failed — .git/worktrees/ may be corrupted")
    fail=1
  fi
}

# --- Checks ---

# Orphans MUST be gone
assert_gone "autoimprove/orphan-1"
assert_gone "worktree-agent-orphan-2"

# Protected branches MUST still point at their original SHAs
assert_exists_at "autoimprove/kept-alpha" "${PILOT_SHA_KEPT_ALPHA:-}"
assert_exists_at "autoimprove/999-in-flight" "${PILOT_SHA_IN_FLIGHT:-}"

# Protected tag MUST still point at the keeper's commit
assert_tag_at "exp-alpha" "${PILOT_SHA_EXP_ALPHA_TAG:-}"

# main MUST NOT be touched
assert_main_unchanged

# experiments/999/context.json MUST NOT be modified
assert_context_intact

# Git repo MUST be healthy after the operation
assert_git_healthy

if [ $fail -ne 0 ]; then
  printf 'FAIL:\n'
  for f in "${fails[@]}"; do printf '  - %s\n' "$f"; done
  exit 1
fi

echo "PASS"
exit 0
