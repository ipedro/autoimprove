#!/usr/bin/env bash
# evaluate.sh — Gate runner for autoimprove
# Usage: evaluate.sh <config.json> <baseline.json>
# Outputs a JSON verdict to stdout. Exit code is always 0 (verdict is in JSON).
# Requires: bash 4+, jq, python3 (for ms timing on macOS)

set -uo pipefail

CONFIG="${1:-}"
BASELINE="${2:-}"

if [ -z "$CONFIG" ] || [ -z "$BASELINE" ]; then
  echo '{"verdict":"error","reason":"usage: evaluate.sh <config.json> <baseline.json>"}' >&2
  exit 1
fi

if [ ! -f "$CONFIG" ]; then
  echo "{\"verdict\":\"error\",\"reason\":\"config not found: $CONFIG\"}" >&2
  exit 1
fi

# Determine mode: init if baseline is /dev/null or missing
INIT_MODE=false
if [ "$BASELINE" = "/dev/null" ] || [ ! -f "$BASELINE" ]; then
  INIT_MODE=true
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

now_ms() {
  local t
  t=$(date +%s%3N 2>/dev/null)
  # macOS date returns e.g. "17744763243N" — fall back to python3 if not pure digits
  if [[ "$t" =~ ^[0-9]+$ ]]; then
    echo "$t"
  else
    python3 -c 'import time; print(int(time.time()*1000))'
  fi
}

# ── Gate runner ───────────────────────────────────────────────────────────────
# Returns: sets GATE_RESULTS (JSON array) and GATE_PASSED (bool)

run_gates() {
  local gate_count
  gate_count=$(jq '.gates | length' "$CONFIG")

  GATE_RESULTS='[]'
  GATE_PASSED=true

  for (( i=0; i<gate_count; i++ )); do
    local name cmd
    name=$(jq -r ".gates[$i].name" "$CONFIG")
    cmd=$(jq -r ".gates[$i].command" "$CONFIG")

    local start_ms end_ms duration_ms exit_code
    start_ms=$(now_ms)

    set +e
    eval "$cmd" >/dev/null 2>&1
    exit_code=$?
    set -e

    end_ms=$(now_ms)
    duration_ms=$(( end_ms - start_ms ))

    local passed
    if [ "$exit_code" -eq 0 ]; then
      passed=true
    else
      passed=false
    fi

    local gate_json
    gate_json=$(jq -n \
      --arg name "$name" \
      --argjson passed "$passed" \
      --argjson exit_code "$exit_code" \
      --argjson duration_ms "$duration_ms" \
      '{name: $name, passed: $passed, exit_code: $exit_code, duration_ms: $duration_ms}')

    GATE_RESULTS=$(echo "$GATE_RESULTS" | jq ". + [$gate_json]")

    if [ "$passed" = "false" ]; then
      GATE_PASSED=false
      # Fast-fail: stop after first failure
      return
    fi
  done
}

# ── Main ──────────────────────────────────────────────────────────────────────

run_gates

if [ "$GATE_PASSED" = "false" ]; then
  jq -n \
    --arg verdict "gate_fail" \
    --argjson gates "$GATE_RESULTS" \
    '{verdict: $verdict, gates: $gates}'
  exit 0
fi

# All gates passed
if [ "$INIT_MODE" = "true" ]; then
  jq -n \
    --argjson gates "$GATE_RESULTS" \
    '{mode: "init", gates: $gates, metrics: {}}'
else
  # Check if any benchmarks are configured
  benchmark_count=$(jq '.benchmarks | length' "$CONFIG")
  if [ "$benchmark_count" -eq 0 ]; then
    jq -n \
      --argjson gates "$GATE_RESULTS" \
      '{verdict: "neutral", reason: "no benchmarks configured", gates: $gates, metrics: {}, improved: [], regressed: [], verdict_logic: "no_benchmarks"}'
  else
    # Benchmarks present — scoring not yet implemented (future task)
    jq -n \
      --argjson gates "$GATE_RESULTS" \
      '{verdict: "neutral", reason: "benchmark scoring not yet implemented", gates: $gates, metrics: {}, improved: [], regressed: [], verdict_logic: "pending"}'
  fi
fi
