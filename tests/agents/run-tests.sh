#!/usr/bin/env bash
# Test runner for autoimprove agent tests
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

echo "========================================"
echo " autoimprove Agent Test Suite"
echo "========================================"
echo ""
echo "Project: $(cd ../.. && pwd)"
echo "Time: $(date)"
echo "Claude: $(claude --version 2>/dev/null || echo 'not found')"
echo ""

if ! command -v claude &>/dev/null; then
    echo "ERROR: claude CLI not found"
    exit 1
fi

if ! command -v python3 &>/dev/null; then
    echo "ERROR: python3 required for JSON assertions"
    exit 1
fi

VERBOSE=false
SPECIFIC_TEST=""
TIMEOUT=120

while [[ $# -gt 0 ]]; do
    case $1 in
        --verbose|-v) VERBOSE=true; shift ;;
        --test|-t) SPECIFIC_TEST="$2"; shift 2 ;;
        --timeout) TIMEOUT="$2"; shift 2 ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

tests=(
    "test-judge.sh"
    "test-enthusiast.sh"
    "test-adversary.sh"
)

[ -n "$SPECIFIC_TEST" ] && tests=("$SPECIFIC_TEST")

passed=0; failed=0; skipped=0

for test in "${tests[@]}"; do
    echo "----------------------------------------"
    echo "Running: $test"
    echo "----------------------------------------"

    test_path="$SCRIPT_DIR/$test"

    if [ ! -f "$test_path" ]; then
        echo "  [SKIP] not found: $test"
        skipped=$((skipped+1))
        continue
    fi

    chmod +x "$test_path"
    start=$(date +%s)

    if [ "$VERBOSE" = true ]; then
        if timeout "$TIMEOUT" bash "$test_path"; then
            echo "  [PASS] (${$(( $(date +%s) - start ))}s)"
            passed=$((passed+1))
        else
            echo "  [FAIL]"
            failed=$((failed+1))
        fi
    else
        if output=$(timeout "$TIMEOUT" bash "$test_path" 2>&1); then
            echo "$output"
            passed=$((passed+1))
        else
            echo "$output"
            failed=$((failed+1))
        fi
    fi
    echo ""
done

echo "========================================"
echo " Results: passed=$passed failed=$failed skipped=$skipped"
echo "========================================"

[ $failed -eq 0 ] || exit 1
