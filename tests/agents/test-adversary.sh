#!/usr/bin/env bash
# Tests for agents/adversary.md
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/test-helpers.sh"

echo "=== Test: adversary agent ==="
echo ""
passed=0; failed=0

run_test() {
    if "$@"; then passed=$((passed+1)); else failed=$((failed+1)); fi
}

# ---------------------------------------------------------------------------
# Test 1: empty findings → empty verdicts
# ---------------------------------------------------------------------------
echo "Test 1: empty findings → {\"verdicts\": []}"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>// clean code, no issues</code>

<findings>{\"findings\":[]}</findings>

Respond with only the JSON verdicts object.
" 60)

run_test assert_json_has_key "$output" "verdicts" "verdicts key present"
run_test assert_json_array_length "$output" "verdicts" "0" "empty verdicts for empty findings"

echo ""

# ---------------------------------------------------------------------------
# Test 2: every finding gets a verdict (no skipping)
# ---------------------------------------------------------------------------
echo "Test 2: one verdict per finding — no skipping"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// db.ts
function query(sql, params) {
  return connection.execute(sql + params);
}
</code>

<findings>
{\"findings\":[
  {\"id\":\"F1\",\"severity\":\"critical\",\"file\":\"db.ts\",\"line\":2,\"description\":\"SQL injection\",\"evidence\":\"params concatenated directly into sql string\",\"prior_finding_id\":null},
  {\"id\":\"F2\",\"severity\":\"medium\",\"file\":\"db.ts\",\"line\":1,\"description\":\"No input validation\",\"evidence\":\"params not validated before use\",\"prior_finding_id\":null}
]}
</findings>

Respond with only the JSON verdicts object.
" 90)

run_test assert_json_has_key "$output" "verdicts" "verdicts key present"
run_test assert_json_array_length "$output" "verdicts" "2" "two verdicts for two findings"

# Verify finding IDs match
json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
ids = {v['finding_id'] for v in d.get('verdicts',[])}
expected = {'F1','F2'}
missing = expected - ids
extra = ids - expected
if missing or extra:
    print('mismatch: missing=' + str(missing) + ' extra=' + str(extra))
else:
    print('ok')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] finding IDs match (F1, F2)"
        passed=$((passed+1))
    else
        echo "  [FAIL] $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Test 3: verdict values are within allowed set
# ---------------------------------------------------------------------------
echo "Test 3: verdict values are only valid|debunked|partial"

output=$(run_as_agent "adversary.md" "
Review the Enthusiast's findings and challenge them.

<code>
// config.ts
const API_KEY = 'sk-abc123';
export { API_KEY };
</code>

<findings>
{\"findings\":[{\"id\":\"F1\",\"severity\":\"high\",\"file\":\"config.ts\",\"line\":1,\"description\":\"Hardcoded API key\",\"evidence\":\"API_KEY is a hardcoded string literal\",\"prior_finding_id\":null}]}
</findings>

Respond with only the JSON verdicts object.
" 90)

json=$(extract_json "$output" 2>/dev/null || echo "")
if [ -n "$json" ]; then
    result=$(echo "$json" | python3 -c "
import sys, json
d = json.load(sys.stdin)
allowed = {'valid','debunked','partial'}
bad = [v['finding_id'] for v in d.get('verdicts',[]) if v.get('verdict') not in allowed]
print('bad:' + ','.join(bad) if bad else 'ok')
" 2>/dev/null)
    if [ "$result" = "ok" ]; then
        echo "  [PASS] all verdict values are valid"
        passed=$((passed+1))
    else
        echo "  [FAIL] invalid verdict values: $result"
        failed=$((failed+1))
    fi
fi

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "=== adversary: passed=$passed failed=$failed ==="
[ $failed -eq 0 ] || exit 1
