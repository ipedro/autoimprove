#!/usr/bin/env bash
# Tests for agents/judge.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: judge agent ==="
echo ""
passed=0; failed=0

run_test() {
    if "$@"; then passed=$((passed+1)); else failed=$((failed+1)); fi
}

# ---------------------------------------------------------------------------
# Test 1: convergence must be false on round 1
# ---------------------------------------------------------------------------
echo "Test 1: convergence=false on round 1 (critical invariant)"

output=$(run_as_agent "judge.md" "
You are the judge. This is round 1 — no prior rulings exist.

<code>
// src/foo.ts
function greet(user) {
  return 'Hello ' + user.name;
}
</code>

<findings>
{\"findings\":[{\"id\":\"F1\",\"severity\":\"high\",\"file\":\"src/foo.ts\",\"line\":2,\"description\":\"Null dereference on user.name\",\"evidence\":\"user parameter not checked for null before accessing .name\",\"prior_finding_id\":null}]}
</findings>

<verdicts>
{\"verdicts\":[{\"finding_id\":\"F1\",\"verdict\":\"valid\",\"severity_adjustment\":null,\"reasoning\":\"user.name is accessed without null guard\"}]}
</verdicts>

Respond with only the JSON ruling object.
" 90)

run_test assert_json_field "$output" "convergence" "False" "convergence is False on round 1"
run_test assert_json_has_key "$output" "rulings" "rulings key present"
run_test assert_json_has_key "$output" "summary" "summary key present"

echo ""

# ---------------------------------------------------------------------------
# Test 2: empty findings → empty rulings
# ---------------------------------------------------------------------------
echo "Test 2: empty findings produces empty rulings array"

output=$(run_as_agent "judge.md" "
You are the judge. Round 1.

<code>// clean file with no issues</code>

<findings>{\"findings\":[]}</findings>
<verdicts>{\"verdicts\":[]}</verdicts>

Respond with only the JSON ruling object.
" 60)

run_test assert_json_array_length "$output" "rulings" "0" "rulings array is empty"
run_test assert_json_field "$output" "convergence" "False" "convergence false even with empty findings"

echo ""

# ---------------------------------------------------------------------------
# Test 3: valid JSON structure with required fields
# ---------------------------------------------------------------------------
echo "Test 3: output is valid JSON with all required fields"

output=$(run_as_agent "judge.md" "
Round 1. One finding to rule on.

<code>
// auth.ts line 5: password stored in plaintext
const password = req.body.password;
db.save({ password });
</code>

<findings>
{\"findings\":[{\"id\":\"F1\",\"severity\":\"critical\",\"file\":\"auth.ts\",\"line\":5,\"description\":\"Plaintext password storage\",\"evidence\":\"password saved directly to db without hashing\",\"prior_finding_id\":null}]}
</findings>

<verdicts>
{\"verdicts\":[{\"finding_id\":\"F1\",\"verdict\":\"valid\",\"severity_adjustment\":null,\"reasoning\":\"Confirmed: db.save receives raw password\"}]}
</verdicts>

Respond with only the JSON ruling object.
" 90)

run_test assert_json_has_key "$output" "rulings" "has rulings"
run_test assert_json_has_key "$output" "summary" "has summary"
run_test assert_json_has_key "$output" "convergence" "has convergence"
run_test assert_json_array_length "$output" "rulings" "1" "one ruling for one finding"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== judge: passed=$passed failed=$failed ==="
[ $failed -eq 0 ] || exit 1
