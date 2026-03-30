#!/usr/bin/env bash
# ar-effectiveness.sh — Benchmark adversarial-review skill effectiveness
# Emits: {"ar_precision": float, "ar_quality_score": int, "cases_run": int, "cases_passed": int}
set -uo pipefail

DIR="$(cd "$(dirname "$0")/.." && pwd)"
GOLDEN_DIR="$DIR/benchmark/ar-golden"
JUDGE_PROMPT_FILE="$DIR/benchmark/judge-prompt.txt"

# --- Guard: claude CLI must be present ---
if ! command -v claude &>/dev/null; then
  echo '{"ar_precision": -1, "ar_quality_score": -1, "error": "claude CLI not found"}'
  exit 0
fi

# ============================================================
# Measurement 1: AR Precision (golden test cases)
# ============================================================
total_cases=0
passed_cases=0
precision_sum=0

if [ -d "$GOLDEN_DIR" ]; then
  for case_dir in "$GOLDEN_DIR"/case-*/; do
    [ -d "$case_dir" ] || continue

    diff_file="$case_dir/diff.txt"
    expected_file="$case_dir/expected.txt"

    # Skip if either file is missing
    [ -f "$diff_file" ] || continue
    [ -f "$expected_file" ] || continue

    total_cases=$((total_cases + 1))

    # Run AR on this diff
    ar_output=$(claude --print --model haiku \
      -p "Review this diff and list all bugs, issues, and improvements. Be thorough. Output one finding per line in format: severity:category:description

$(cat "$diff_file")" 2>/dev/null || true)

    # Fuzzy match: check how many expected category keywords appear in AR output
    total_expected=0
    found=0
    while IFS= read -r line; do
      [ -z "$line" ] && continue
      total_expected=$((total_expected + 1))
      # Extract the category (second colon-delimited field, or full line if no colon)
      keyword=$(echo "$line" | cut -d: -f2 | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      [ -z "$keyword" ] && keyword=$(echo "$line" | tr '[:upper:]' '[:lower:]' | tr -d ' ')
      if echo "$ar_output" | tr '[:upper:]' '[:lower:]' | grep -qF "$keyword" 2>/dev/null; then
        found=$((found + 1))
      fi
    done < "$expected_file"

    if [ "$total_expected" -gt 0 ]; then
      # Use awk for float division
      case_rate=$(awk "BEGIN { printf \"%.4f\", $found / $total_expected }")
      precision_sum=$(awk "BEGIN { printf \"%.4f\", $precision_sum + $case_rate }")
      # A case is "passed" if match_rate >= 0.5
      is_passed=$(awk "BEGIN { print ($case_rate >= 0.5) ? 1 : 0 }")
      passed_cases=$((passed_cases + is_passed))
    fi
  done
fi

# Average precision across cases
if [ "$total_cases" -gt 0 ]; then
  ar_precision=$(awk "BEGIN { printf \"%.4f\", $precision_sum / $total_cases }")
else
  ar_precision="0"
fi

# ============================================================
# Measurement 2: AR Quality (LLM-as-judge)
# ============================================================
ar_quality_score=-1
TMP_AR_OUTPUT=$(mktemp /tmp/ar-output.XXXXXX)

# Use case-01 as canonical input; fall back to a trivial diff if not present
canonical_diff="$GOLDEN_DIR/case-01/diff.txt"
if [ ! -f "$canonical_diff" ]; then
  # No golden cases yet — create an ephemeral minimal diff for judge evaluation
  TMP_DIFF=$(mktemp /tmp/ar-diff.XXXXXX)
  cat > "$TMP_DIFF" <<'EOF'
diff --git a/foo.py b/foo.py
index 0000000..1111111 100644
--- a/foo.py
+++ b/foo.py
@@ -1,3 +1,6 @@
 def divide(a, b):
-    return a / b
+    result = a / b  # potential division by zero
+    return result
+
+x = divide(10, 0)
EOF
  canonical_diff="$TMP_DIFF"
fi

claude --print --model haiku \
  -p "Review this diff and list all bugs, issues, and improvements. Be thorough. Output one finding per line in format: severity:category:description

$(cat "$canonical_diff")" 2>/dev/null > "$TMP_AR_OUTPUT" || true

# Only run judge if we have a judge prompt and the AR produced output
if [ -f "$JUDGE_PROMPT_FILE" ] && [ -s "$TMP_AR_OUTPUT" ]; then
  JUDGE_PROMPT=$(cat "$JUDGE_PROMPT_FILE")
  AR_OUTPUT=$(cat "$TMP_AR_OUTPUT")

  judge_response=$(claude --print --model sonnet \
    -p "${JUDGE_PROMPT}

${AR_OUTPUT}" 2>/dev/null || true)

  # Extract "total" field from JSON response; tolerate non-JSON gracefully
  extracted=$(echo "$judge_response" | \
    python3 -c "
import sys, json, re
raw = sys.stdin.read()
# Try strict JSON parse first
try:
    data = json.loads(raw)
    print(int(data.get('total', -1)))
    sys.exit(0)
except Exception:
    pass
# Fallback: regex for \"total\": <number>
m = re.search(r'[\"'\"'\"total[\"'\"'\"]\\s*:\\s*([0-9]+)', raw)
if m:
    print(m.group(1))
else:
    print(-1)
" 2>/dev/null || echo "-1")

  ar_quality_score="$extracted"
fi

# Cleanup
rm -f "$TMP_AR_OUTPUT"
[ -n "${TMP_DIFF:-}" ] && rm -f "$TMP_DIFF"

# ============================================================
# Output JSON
# ============================================================
echo "{\"ar_precision\": $ar_precision, \"ar_quality_score\": $ar_quality_score, \"cases_run\": $total_cases, \"cases_passed\": $passed_cases}"
