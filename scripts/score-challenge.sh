#!/usr/bin/env bash
# score-challenge.sh — Score a challenge findings file against an answer key
# Usage: score-challenge.sh <answer-key.json> <findings.json>
# Outputs a JSON score object to stdout. Exit code is always 0.
# Requires: bash 4+, jq

set -uo pipefail

ANSWER_KEY="${1:-}"
FINDINGS="${2:-}"

if [ -z "$ANSWER_KEY" ] || [ -z "$FINDINGS" ]; then
  echo '{"error":"usage: score-challenge.sh <answer-key.json> <findings.json>"}' >&2
  exit 1
fi

if [ ! -f "$ANSWER_KEY" ]; then
  echo "{\"error\":\"answer key not found: $ANSWER_KEY\"}" >&2
  exit 1
fi

if [ ! -f "$FINDINGS" ]; then
  echo "{\"error\":\"findings not found: $FINDINGS\"}" >&2
  exit 1
fi

# ── Read scoring config ────────────────────────────────────────────────────────

MATCH_FILE=$(jq -r '.scoring.match_file // true' "$ANSWER_KEY")
MATCH_LINE_RANGE=$(jq -r '.scoring.match_line_range // 3' "$ANSWER_KEY")

# ── Count answer key bugs ──────────────────────────────────────────────────────

NUM_BUGS=$(jq '.bugs | length' "$ANSWER_KEY")

# ── Identify confirmed findings ────────────────────────────────────────────────
# Confirmed = winner != "adversary" AND final_severity != "dismissed"

# Build confirmed IDs array (F1: safe pipeline with fallback)
CONFIRMED_IDS_JSON=$(jq '
  [
    .rulings
    | map(select(.winner != "adversary" and .final_severity != "dismissed"))
    | .[].finding_id
  ]' "$FINDINGS" 2>/dev/null) || CONFIRMED_IDS_JSON='[]'

# Build confirmed findings with deduplication on ID (F17: prevents TP inflation from dupe IDs)
CONFIRMED_FINDINGS=$(jq --argjson confirmed_ids "${CONFIRMED_IDS_JSON}" '
  .findings
  | map(select(.id as $id | $confirmed_ids | contains([$id])))
  | unique_by(.id)
' "$FINDINGS" 2>/dev/null) || CONFIRMED_FINDINGS='[]'

[ -z "$CONFIRMED_FINDINGS" ] && CONFIRMED_FINDINGS='[]'

TOTAL_CONFIRMED=$(echo "$CONFIRMED_FINDINGS" | jq 'length')

# ── Match bugs to confirmed findings ──────────────────────────────────────────
# For each bug in answer key, find a confirmed finding that matches:
#   same file (if match_file=true) AND line within match_line_range
# F2: findings with non-numeric .line are skipped (type guard in jq)

TP=0
MATCHED_FINDING_IDS='[]'

BUG_COUNT=$(jq '.bugs | length' "$ANSWER_KEY")

for (( i=0; i<BUG_COUNT; i++ )); do
  BUG_FILE=$(jq -r ".bugs[$i].file" "$ANSWER_KEY")
  BUG_LINE=$(jq -r ".bugs[$i].line" "$ANSWER_KEY")

  # Find a confirmed finding that matches this bug (not already matched)
  MATCH_ID=$(echo "$CONFIRMED_FINDINGS" | jq -r \
    --arg file "$BUG_FILE" \
    --argjson line "$BUG_LINE" \
    --argjson range "$MATCH_LINE_RANGE" \
    --argjson match_file "$MATCH_FILE" \
    --argjson already_matched "$MATCHED_FINDING_IDS" \
    '
    map(
      select(
        (.id as $id | $already_matched | contains([$id]) | not)
        and (if $match_file then .file == $file else true end)
        and ((.line | type) == "number")
        and ((.line - $line) | if . < 0 then . * -1 else . end) <= $range
      )
    )
    | first
    | .id // empty
    ' 2>/dev/null || true)

  if [ -n "$MATCH_ID" ]; then
    ((TP++)) || true
    MATCHED_FINDING_IDS=$(echo "$MATCHED_FINDING_IDS" | jq --arg id "$MATCH_ID" '. + [$id]')
  fi
done

FN=$(( NUM_BUGS - TP ))
FP=$(( TOTAL_CONFIRMED - TP ))
[ "$FP" -lt 0 ] && FP=0  # F17: guard against negative FP from dedup edge cases

# ── Calculate precision, recall, F1 ───────────────────────────────────────────

PRECISION=$(jq -n \
  --argjson tp "$TP" \
  --argjson fp "$FP" \
  'if ($tp + $fp) == 0 then 0 else $tp / ($tp + $fp) end')

RECALL=$(jq -n \
  --argjson tp "$TP" \
  --argjson num_bugs "$NUM_BUGS" \
  'if $num_bugs == 0 then 0 else $tp / $num_bugs end')

F1=$(jq -n \
  --argjson precision "$PRECISION" \
  --argjson recall "$RECALL" \
  'if ($precision + $recall) == 0 then 0 else 2 * $precision * $recall / ($precision + $recall) end')

PASS=$(jq -n --argjson f1 "$F1" 'if $f1 >= 0.5 then true else false end')

# ── Output ─────────────────────────────────────────────────────────────────────

jq -n \
  --argjson true_positives "$TP" \
  --argjson false_positives "$FP" \
  --argjson false_negatives "$FN" \
  --argjson precision "$PRECISION" \
  --argjson recall "$RECALL" \
  --argjson f1 "$F1" \
  --argjson pass "$PASS" \
  '{
    true_positives: $true_positives,
    false_positives: $false_positives,
    false_negatives: $false_negatives,
    precision: $precision,
    recall: $recall,
    f1: $f1,
    pass: $pass
  }'
