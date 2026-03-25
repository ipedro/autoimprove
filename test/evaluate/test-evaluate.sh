#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
EVALUATE="$SCRIPT_DIR/../../scripts/evaluate.sh"
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

echo "=== Gate Runner Tests ==="

echo "--- Test: all gates pass ---"
result=$("$EVALUATE" "$FIXTURES/config-gates-only.json" /dev/null 2>/dev/null)
assert_json_field "gates[0] passed" "$result" '.gates[0].passed' 'true'
assert_json_field "gates[1] passed" "$result" '.gates[1].passed' 'true'
assert_json_field "gates[0] name" "$result" '.gates[0].name' 'true-gate'

echo "--- Test: gate failure fast-fails ---"
fail_config='{"gates":[{"name":"fail-gate","command":"false"},{"name":"never-reached","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}'
tmpconfig=$(mktemp)
echo "$fail_config" > "$tmpconfig"
result=$("$EVALUATE" "$tmpconfig" /dev/null 2>/dev/null)
assert_json_field "verdict is gate_fail" "$result" '.verdict' 'gate_fail'
assert_json_field "failed gate name" "$result" '.gates[0].name' 'fail-gate'
assert_json_field "failed gate passed=false" "$result" '.gates[0].passed' 'false'
second_gate=$(echo "$result" | jq '.gates | length')
assert_eq "only one gate ran (fast-fail)" "1" "$second_gate"
rm -f "$tmpconfig"

echo ""
echo "=== Benchmark Runner Tests ==="

bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"

echo "--- Test: init mode extracts metrics ---"
result=$("$EVALUATE" "$bench_config" /dev/null 2>/dev/null)
assert_json_field "mode is init" "$result" '.mode' 'init'
assert_json_field "score extracted" "$result" '.metrics.score' '42'
assert_json_field "speed_ms extracted" "$result" '.metrics.speed_ms' '150'

echo "--- Test: json: extractor works ---"
assert_json_field "score is number" "$result" '.metrics.score | type' 'number'

rm -f "$bench_config"

echo ""
echo "=== Scoring Tests ==="

# Test: keep verdict — both metrics improved
echo "--- Test: keep verdict (both metrics improved) ---"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
# baseline: score=40, speed_ms=160 → candidate: score=42 (+5%), speed_ms=150 (+6.25% normalized)
result=$("$EVALUATE" "$bench_config" "$FIXTURES/baseline-basic.json" 2>/dev/null)
assert_json_field "verdict is keep" "$result" '.verdict' 'keep'
assert_json_field "score in improved" "$result" '.improved | contains(["score"])' 'true'
assert_json_field "speed_ms in improved" "$result" '.improved | contains(["speed_ms"])' 'true'
assert_json_field "regressed is empty" "$result" '.regressed | length' '0'
assert_json_field "score baseline" "$result" '.metrics.score.baseline' '40'
assert_json_field "score candidate" "$result" '.metrics.score.candidate' '42'
rm -f "$bench_config"

# Test: regress verdict — baseline score=50, candidate=42 → -16% regression
echo "--- Test: regress verdict (score regressed) ---"
regress_baseline=$(mktemp)
echo '{"metrics":{"score":50,"speed_ms":160},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$regress_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$regress_baseline" 2>/dev/null)
assert_json_field "verdict is regress" "$result" '.verdict' 'regress'
assert_json_field "score in regressed" "$result" '.regressed | contains(["score"])' 'true'
rm -f "$bench_config" "$regress_baseline"

# Test: neutral verdict — baseline matches candidate exactly
echo "--- Test: neutral verdict (no change) ---"
neutral_baseline=$(mktemp)
echo '{"metrics":{"score":42,"speed_ms":150},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}' > "$neutral_baseline"
bench_config=$(mktemp)
sed "s|FIXTURES_DIR|$FIXTURES|g" "$FIXTURES/config-basic.json" > "$bench_config"
result=$("$EVALUATE" "$bench_config" "$neutral_baseline" 2>/dev/null)
assert_json_field "verdict is neutral" "$result" '.verdict' 'neutral'
assert_json_field "improved is empty" "$result" '.improved | length' '0'
assert_json_field "regressed is empty" "$result" '.regressed | length' '0'
rm -f "$bench_config" "$neutral_baseline"

echo ""
echo "=== Integration Tests (test-project) ==="

TEST_PROJECT="$SCRIPT_DIR/../../test-project"

# Test 1: Gate failure with real test-project (has a failing test)
echo "--- Test: gate fail with real test-project ---"
tp_gate_config=$(mktemp)
cat > "$tp_gate_config" <<EOF
{
  "gates": [
    {"name": "node-tests", "command": "cd $TEST_PROJECT && node --test test/*.test.js"}
  ],
  "benchmarks": [],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$tp_gate_config" /dev/null 2>/dev/null)
assert_json_field "tp gate_fail verdict" "$result" '.verdict' 'gate_fail'
assert_json_field "tp failing gate name" "$result" '.gates[0].name' 'node-tests'
assert_json_field "tp failing gate passed=false" "$result" '.gates[0].passed' 'false'
rm -f "$tp_gate_config"

# Test 2: Init mode with real benchmarks
echo "--- Test: init mode with real benchmark ---"
tp_bench_config=$(mktemp)
cat > "$tp_bench_config" <<EOF
{
  "gates": [
    {"name": "always-pass", "command": "true"}
  ],
  "benchmarks": [
    {
      "name": "real-metrics",
      "command": "bash $TEST_PROJECT/benchmark/metrics.sh",
      "metrics": [
        {
          "name": "test_count",
          "extract": "json:.test_count",
          "direction": "higher_is_better",
          "tolerance": 0.02,
          "significance": 0.01
        }
      ]
    }
  ],
  "regression_tolerance": 0.02,
  "significance_threshold": 0.01
}
EOF
result=$("$EVALUATE" "$tp_bench_config" /dev/null 2>/dev/null)
assert_json_field "tp init mode" "$result" '.mode' 'init'
actual_test_count=$(echo "$result" | jq -r '.metrics.test_count')
if [ "$actual_test_count" -gt 0 ] 2>/dev/null; then
  echo "  PASS: test_count > 0 (got $actual_test_count)"
  ((PASS++)) || true
else
  echo "  FAIL: test_count > 0 (got $actual_test_count)"
  ((FAIL++)) || true
fi

# Test 3: Scoring against real baseline (neutral — no change)
echo "--- Test: neutral verdict against real baseline ---"
# Use the same bench config from test 2 — run init to capture current metrics
init_result=$("$EVALUATE" "$tp_bench_config" /dev/null 2>/dev/null)
raw_test_count=$(echo "$init_result" | jq -r '.metrics.test_count')
tp_baseline=$(mktemp)
cat > "$tp_baseline" <<EOF
{"metrics":{"test_count":$raw_test_count},"sha":"abc123","timestamp":"2026-03-25T00:00:00Z"}
EOF
result=$("$EVALUATE" "$tp_bench_config" "$tp_baseline" 2>/dev/null)
assert_json_field "tp neutral verdict" "$result" '.verdict' 'neutral'
assert_json_field "tp no regressions" "$result" '.regressed | length' '0'
rm -f "$tp_bench_config" "$tp_baseline"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || exit 1
