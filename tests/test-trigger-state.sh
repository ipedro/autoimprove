#!/usr/bin/env bash
# tests/test-trigger-state.sh — Tests for autoimprove-trigger.sh state persistence
#
# Covers:
#  1. Lock guard: concurrent run with fresh lock → logs SKIP and exits early
#  2. Rate guard: recent last_run_epoch → logs SKIP: last run
#  3. Stale lock (>60s old) → warns and clears lock
#  4. State file is updated after a run (last_run_epoch written)
#  5. --install copies script to XGH_HOME/scripts/
#
# Does NOT invoke gh CLI. Tests use environment overrides and inspect log/state files.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TRIGGER_SCRIPT="$SCRIPT_DIR/scripts/autoimprove-trigger.sh"

PASS=0; FAIL=0; TOTAL=0

_assert() {
  local desc="$1"
  local expr="$2"
  TOTAL=$((TOTAL + 1))
  if eval "$expr" 2>/dev/null; then
    PASS=$((PASS + 1))
    echo "  PASS: $desc"
  else
    FAIL=$((FAIL + 1))
    echo "  FAIL: $desc"
    echo "    Expression: $expr"
  fi
}

_run_trigger() {
  # Run the trigger and capture its log file output.
  # NOTE: --quiet triggers a set -e incompatibility in log() — use non-quiet mode
  # and suppress stdout. Log file remains the source of truth for assertions.
  local xgh_home="$1"
  XGH_HOME="$xgh_home" bash "$TRIGGER_SCRIPT" >/dev/null 2>&1 || true
}

echo "========================================"
echo " autoimprove-trigger.sh State Tests"
echo "========================================"
echo ""

WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

XGH_HOME="$WORK_DIR/xgh"
STATE_DIR="$XGH_HOME/state"
LOG_DIR="$XGH_HOME/logs"
mkdir -p "$STATE_DIR" "$LOG_DIR"

LOCK_FILE="$STATE_DIR/autoimprove-trigger.lock"
STATE_FILE="$STATE_DIR/autoimprove-last-check.yaml"
LOG_FILE="$LOG_DIR/autoimprove-trigger.log"

# ---------------------------------------------------------------------------
echo "--- Test 1: Fresh lock → run skips and logs SKIP ---"
touch "$LOCK_FILE"
> "$LOG_FILE"  # reset log

_run_trigger "$XGH_HOME"
_assert "log contains SKIP lock held" "grep -q 'SKIP: lock held' '$LOG_FILE'"
rm -f "$LOCK_FILE"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 2: Rate guard — recent last_run_epoch → logs SKIP ---"
NOW=$(date +%s)
python3 -c "
import yaml
state = {'last_run_epoch': $NOW, 'last_run_iso': 'test', 'last_merged_sha': {}}
with open('$STATE_FILE', 'w') as f:
    yaml.dump(state, f)
"
> "$LOG_FILE"
_run_trigger "$XGH_HOME"
_assert "log contains SKIP: last run" "grep -q 'SKIP: last run' '$LOG_FILE'"
rm -f "$STATE_FILE"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 3: Stale lock (>60s) is warned about in log ---"
touch "$LOCK_FILE"
# Backdate lock mtime by 120 seconds
python3 -c "
import os, time
path = '$LOCK_FILE'
old_time = time.time() - 120
os.utime(path, (old_time, old_time))
"
> "$LOG_FILE"
_run_trigger "$XGH_HOME"
_assert "log mentions stale lock warning" "grep -q 'stale lock' '$LOG_FILE'"
_assert "lock file removed after stale-lock run" "[ ! -f '$LOCK_FILE' ]"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 4: State file updated — last_run_epoch written after run ---"
rm -f "$STATE_FILE" "$LOCK_FILE"
# Reset the log
> "$LOG_FILE"
# Run trigger (will skip all repos as no autoimprove.yaml in dev paths)
# but state must still be persisted at end
_run_trigger "$XGH_HOME"
_assert "state file created after run" "[ -f '$STATE_FILE' ]"
_assert "state file has last_run_epoch" "python3 -c \"
import yaml
with open('$STATE_FILE') as f:
    d = yaml.safe_load(f) or {}
assert 'last_run_epoch' in d and int(d['last_run_epoch']) > 0
\" 2>/dev/null"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 5: --install copies script to XGH_HOME/scripts/ ---"
INSTALL_XGH="$WORK_DIR/install-xgh"
mkdir -p "$INSTALL_XGH/state" "$INSTALL_XGH/logs"
OUTPUT=$(XGH_HOME="$INSTALL_XGH" bash "$TRIGGER_SCRIPT" --install 2>&1) && EC=0 || EC=$?
_assert "--install exits 0" "[ '$EC' = '0' ]"
_assert "script copied to scripts/" "[ -f '$INSTALL_XGH/scripts/autoimprove-trigger.sh' ]"
_assert "copied script is executable" "[ -x '$INSTALL_XGH/scripts/autoimprove-trigger.sh' ]"
_assert "output contains 'Installed:'" "echo '$OUTPUT' | grep -q 'Installed:'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 6: Log file is created automatically (dirs created on first run) ---"
FRESH_XGH="$WORK_DIR/fresh-xgh"
# Do NOT pre-create any dirs — trigger should create them
rm -f "$WORK_DIR/fresh-xgh/state/autoimprove-trigger.lock"
_run_trigger "$FRESH_XGH"
_assert "log file created in fresh XGH_HOME" "[ -f '$FRESH_XGH/logs/autoimprove-trigger.log' ]"
_assert "state dir created in fresh XGH_HOME" "[ -d '$FRESH_XGH/state' ]"
echo ""

# ---------------------------------------------------------------------------
echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
