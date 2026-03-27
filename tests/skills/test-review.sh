#!/usr/bin/env bash
# Tests for skills/adversarial-review/SKILL.md
# Covers: unit (content), triggering (naive prompt), explicit (named + no premature work)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: adversarial-review skill ==="
echo ""
passed=0; failed=0

run_test() { if "$@"; then passed=$((passed+1)); else failed=$((failed+1)); fi }

# ---------------------------------------------------------------------------
# UNIT TESTS — content correctness (Type 1)
# ---------------------------------------------------------------------------
echo "--- Unit: content ---"

echo "Test 1: 50-line file → 2 rounds"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: how many rounds for a 50-line file with no flags?")
run_test assert_contains "$output" "2" "50-line → 2 rounds"

echo "Test 2: 1-round range is 1–49 lines"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: what line range maps to 1 round?")
run_test assert_contains "$output" "49\|1.*49" "1-round range upper bound is 49"

echo "Test 3: user 'quick review' reduces rounds by 1"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: what happens when the user says 'quick review' and no --rounds flag is given?")
run_test assert_contains "$output" "reduc\|minus 1\|subtract" "quick review reduces rounds"
run_test assert_contains "$output" "minimum 1\|min.*1\|1 round minimum" "minimum is 1"

echo "Test 4: convergence=true on round 1 is ignored"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: what does the orchestrator do if the judge returns convergence=true on round 1?")
run_test assert_contains "$output" "ignor\|treat.*false\|false" "round-1 convergence is ignored"

echo "Test 5: empty diff response includes alternatives"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: what message is shown when both git diff HEAD and git diff --staged are empty?")
run_test assert_contains "$output" "HEAD~1\|branch\|alternative\|stage" "alternatives mentioned for empty diff"

echo "Test 6: malformed JSON triggers retry"
output=$(run_claude "Read /Users/pedro/Developer/autoimprove/skills/review/SKILL.md and answer: what happens when the enthusiast returns invalid JSON?")
run_test assert_contains "$output" "re-prompt\|retry\|once\|again" "malformed JSON triggers retry"

echo ""

# ---------------------------------------------------------------------------
# TRIGGERING TESTS — naive prompts (Type 3)
# ---------------------------------------------------------------------------
echo "--- Triggering: naive prompts ---"

_check_trigger() {
    local prompt="$1" expect="$2" name="$3"
    local log
    log=$(run_with_plugin "$prompt")
    if [ "$expect" = "yes" ]; then
        run_test assert_skill_triggered "$log" "adversarial-review""$name"
    else
        run_test assert_skill_not_triggered "$log" "adversarial-review""$name"
    fi
    rm -f "$log"
}

echo "Test 7: 'run a review round on my code' triggers"
_check_trigger "run a review round on my code" "yes" "natural phrasing"

echo "Test 8: 'adversarial review' triggers"
_check_trigger "adversarial review" "yes" "adversarial review phrasing"

echo "Test 9: 'review code with debate agents' triggers"
_check_trigger "review code with debate agents" "yes" "debate agents phrasing"

echo "Test 10: 'run the test suite' does NOT trigger review"
_check_trigger "run the test suite" "no" "test suite — no false positive"

echo "Test 11: 'start the improvement loop' does NOT trigger review"
_check_trigger "start the improvement loop" "no" "grind loop — no false positive"

echo ""

# ---------------------------------------------------------------------------
# EXPLICIT REQUEST TESTS — named invocation + no premature work (Type 4)
# ---------------------------------------------------------------------------
echo "--- Explicit: named invocation + no premature work ---"

echo "Test 12: '/autoimprove review' — skill fires, no premature work"
log=$(run_with_plugin "/autoimprove review")
run_test assert_skill_triggered "$log" "adversarial-review""explicit /autoimprove review fires"
run_test assert_no_premature_work "$log" "no work before skill loads"
rm -f "$log"

echo "Test 13: 'run debate review' — skill fires, no premature work"
log=$(run_with_plugin "run debate review")
run_test assert_skill_triggered "$log" "adversarial-review""run debate review fires"
run_test assert_no_premature_work "$log" "no premature work"
rm -f "$log"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== adversarial-review skill: passed=$passed failed=$failed ==="
[ $failed -eq 0 ] || exit 1
