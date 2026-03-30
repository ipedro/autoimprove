#!/usr/bin/env bash
# tests/test-install-hooks.sh — Unit tests for scripts/install-hooks.sh
#
# Tests:
#  1. Symlinks are created for all hooks in scripts/hooks/
#  2. Existing hook is overwritten (idempotent re-install)
#  3. Each installed symlink resolves to the correct source file
#  4. Script outputs "Installed: <name>" for each hook
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
INSTALL_HOOKS="$SCRIPT_DIR/scripts/install-hooks.sh"

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

echo "========================================"
echo " install-hooks.sh Tests"
echo "========================================"
echo ""

# ---------------------------------------------------------------------------
# Setup: fake git repo in a temp dir so git rev-parse --show-toplevel works
# ---------------------------------------------------------------------------
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

# Init a bare git structure (just need .git/hooks)
git -C "$WORK_DIR" init -q
FAKE_HOOKS_SRC="$WORK_DIR/scripts/hooks"
FAKE_HOOKS_DST="$WORK_DIR/.git/hooks"
mkdir -p "$FAKE_HOOKS_SRC"
mkdir -p "$FAKE_HOOKS_DST"

# Create two fake hooks in scripts/hooks/
echo '#!/bin/sh' > "$FAKE_HOOKS_SRC/pre-commit"
echo 'exit 0' >> "$FAKE_HOOKS_SRC/pre-commit"
chmod +x "$FAKE_HOOKS_SRC/pre-commit"

echo '#!/bin/sh' > "$FAKE_HOOKS_SRC/commit-msg"
echo 'exit 0' >> "$FAKE_HOOKS_SRC/commit-msg"
chmod +x "$FAKE_HOOKS_SRC/commit-msg"

# Run install-hooks.sh from within the fake repo
OUTPUT=$(cd "$WORK_DIR" && bash "$INSTALL_HOOKS" 2>&1)
INSTALL_EXIT=$?

# ---------------------------------------------------------------------------
echo "--- Test 1: Script exits 0 ---"
_assert "install-hooks exits 0" "[ '$INSTALL_EXIT' = '0' ]"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 2: Symlinks created for all hooks ---"
_assert "pre-commit symlink exists" "[ -L '$FAKE_HOOKS_DST/pre-commit' ]"
_assert "commit-msg symlink exists" "[ -L '$FAKE_HOOKS_DST/commit-msg' ]"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 3: Symlinks resolve to source files ---"
# Use realpath on both sides to handle macOS /var → /private/var symlink
_assert "pre-commit symlink → scripts/hooks/pre-commit" \
  "[ \"\$(python3 -c 'import os; print(os.path.realpath(os.readlink(\"$FAKE_HOOKS_DST/pre-commit\")))' 2>/dev/null)\" = \"\$(python3 -c 'import os; print(os.path.realpath(\"$FAKE_HOOKS_SRC/pre-commit\"))' 2>/dev/null)\" ]"
_assert "commit-msg symlink → scripts/hooks/commit-msg" \
  "[ \"\$(python3 -c 'import os; print(os.path.realpath(os.readlink(\"$FAKE_HOOKS_DST/commit-msg\")))' 2>/dev/null)\" = \"\$(python3 -c 'import os; print(os.path.realpath(\"$FAKE_HOOKS_SRC/commit-msg\"))' 2>/dev/null)\" ]"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 4: Output announces each installed hook ---"
_assert "output contains 'Installed: pre-commit'" \
  "echo '$OUTPUT' | grep -q 'Installed: pre-commit'"
_assert "output contains 'Installed: commit-msg'" \
  "echo '$OUTPUT' | grep -q 'Installed: commit-msg'"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 5: Idempotent — re-install overwrites existing symlinks ---"
# Place a stale symlink pointing nowhere
ln -sf /dev/null "$FAKE_HOOKS_DST/pre-commit"
OUTPUT2=$(cd "$WORK_DIR" && bash "$INSTALL_HOOKS" 2>&1)
_assert "re-install exits 0" "[ $? = 0 ]"
_assert "pre-commit symlink updated after re-install" \
  "[ \"\$(python3 -c 'import os; print(os.path.realpath(os.readlink(\"$FAKE_HOOKS_DST/pre-commit\")))' 2>/dev/null)\" = \"\$(python3 -c 'import os; print(os.path.realpath(\"$FAKE_HOOKS_SRC/pre-commit\"))' 2>/dev/null)\" ]"
echo ""

# ---------------------------------------------------------------------------
echo "--- Test 6: No hooks → script still exits 0 (empty hooks dir) ---"
WORK_DIR2=$(mktemp -d)
git -C "$WORK_DIR2" init -q
mkdir -p "$WORK_DIR2/scripts/hooks"
mkdir -p "$WORK_DIR2/.git/hooks"
EMPTY_OUTPUT=$(cd "$WORK_DIR2" && bash "$INSTALL_HOOKS" 2>&1)
EMPTY_EXIT=$?
_assert "empty hooks dir: exit 0" "[ '$EMPTY_EXIT' = '0' ]"
rm -rf "$WORK_DIR2"
echo ""

# ---------------------------------------------------------------------------
echo "========================================"
echo " Results: $PASS/$TOTAL passed, $FAIL failed"
echo "========================================"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
