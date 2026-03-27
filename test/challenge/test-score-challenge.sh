#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SCORE="$SCRIPT_DIR/../../scripts/score-challenge.sh"
FIXTURES="$SCRIPT_DIR/fixtures"
PASS=0
FAIL=0

assert_eq() {
  local desc="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  PASS: $desc"
    ((PASS++)) || true
  else
    echo "  FAIL: $desc"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    ((FAIL++)) || true
  fi
}

assert_json_field() {
  local desc="$1" json="$2" field="$3" expected="$4"
  local actual
  actual=$(echo "$json" | jq -r "$field")
  assert_eq "$desc" "$expected" "$actual"
}

echo "=== Challenge Scoring Tests ==="

echo ""
echo "--- Test: perfect case (2/2 bugs, 0 false positives) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-good.json" 2>/dev/null)
assert_json_field "true_positives=2" "$result" '.true_positives' '2'
assert_json_field "false_positives=0" "$result" '.false_positives' '0'
assert_json_field "false_negatives=0" "$result" '.false_negatives' '0'
assert_json_field "precision=1" "$result" '.precision' '1'
assert_json_field "recall=1" "$result" '.recall' '1'
assert_json_field "f1=1" "$result" '.f1' '1'
assert_json_field "pass=true" "$result" '.pass' 'true'

echo ""
echo "--- Test: noisy case (2/2 bugs, 3 false positives) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-noisy.json" 2>/dev/null)
assert_json_field "true_positives=2" "$result" '.true_positives' '2'
assert_json_field "false_positives=3" "$result" '.false_positives' '3'
assert_json_field "false_negatives=0" "$result" '.false_negatives' '0'
assert_json_field "recall=1" "$result" '.recall' '1'
# precision = 2/5 = 0.4
assert_json_field "precision=0.4" "$result" '.precision' '0.4'
# f1 = 2*(0.4*1)/(0.4+1) = 0.8/1.4 ≈ 0.571 → pass=true (f1 > 0.5)
assert_json_field "pass=true" "$result" '.pass' 'true'

echo ""
echo "--- Test: empty case (0 findings) ---"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$FIXTURES/sample-findings-empty.json" 2>/dev/null)
assert_json_field "true_positives=0" "$result" '.true_positives' '0'
assert_json_field "false_positives=0" "$result" '.false_positives' '0'
assert_json_field "false_negatives=2" "$result" '.false_negatives' '2'
assert_json_field "precision=0" "$result" '.precision' '0'
assert_json_field "recall=0" "$result" '.recall' '0'
assert_json_field "f1=0" "$result" '.f1' '0'
assert_json_field "pass=false" "$result" '.pass' 'false'

echo ""
echo "--- Test: null line in finding (F2 regression) ---"
NULL_LINE_FINDINGS='{
  "rulings": [
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid"}
  ],
  "findings": [
    {"id": "F1", "file": "challenge.py", "line": null, "severity": "high", "description": "Bug"}
  ]
}'
tmpfile=$(mktemp)
echo "$NULL_LINE_FINDINGS" > "$tmpfile"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$tmpfile" 2>/dev/null)
rm "$tmpfile"
assert_json_field "null line: true_positives=0 (not a crash)" "$result" '.true_positives' '0'
assert_json_field "null line: false_positives=1 (confirmed but no match)" "$result" '.false_positives' '1'
assert_json_field "null line: pass=false" "$result" '.pass' 'false'

echo ""
echo "--- Test: duplicate finding IDs (F17 regression) ---"
DUPE_FINDINGS='{
  "rulings": [
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid"},
    {"finding_id": "F1", "final_severity": "high", "winner": "enthusiast", "resolution": "Valid dupe"}
  ],
  "findings": [
    {"id": "F1", "file": "challenge.py", "line": 12, "severity": "high", "description": "Bug"},
    {"id": "F1", "file": "challenge.py", "line": 12, "severity": "high", "description": "Bug dupe"}
  ]
}'
tmpfile=$(mktemp)
echo "$DUPE_FINDINGS" > "$tmpfile"
result=$("$SCORE" "$FIXTURES/sample-answer-key.json" "$tmpfile" 2>/dev/null)
rm "$tmpfile"
assert_json_field "dupe IDs: false_positives=0 (not negative)" "$result" '.false_positives' '0'
assert_json_field "dupe IDs: true_positives=1" "$result" '.true_positives' '1'
fp_val=$(echo "$result" | jq -r '.false_positives')
if [ "$fp_val" -ge 0 ] 2>/dev/null; then
  echo "  PASS: false_positives is non-negative ($fp_val)"
  ((PASS++)) || true
else
  echo "  FAIL: false_positives is negative ($fp_val)"
  ((FAIL++)) || true
fi

echo ""
echo "=== Results: $PASS passed, $FAIL failed ==="
[ "$FAIL" -eq 0 ] || exit 1
