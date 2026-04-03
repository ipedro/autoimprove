#!/usr/bin/env bash
# Shared helpers for autoimprove skill unit tests.
# Pattern: ask natural language questions about skill content, assert on output.
# Cross-platform (macOS + Linux) — no GNU timeout dependency.
# Reference: superpowers/tests/claude-code/test-helpers.sh

TEST_MODEL="${TEST_MODEL:-haiku}"
PLUGIN_DIR="${PLUGIN_DIR:-$(cd "$(dirname "$0")/../.." && pwd)}"

# Run claude with a natural language prompt, capture text output.
# Usage: run_claude "In the X skill, what is Y?" [max_turns]
run_claude() {
    local prompt="$1"
    local max_turns="${2:-3}"
    claude -p "$prompt" \
        --model "$TEST_MODEL" \
        --output-format text \
        --max-turns "$max_turns" \
        2>/dev/null
}

# Run triggering test — loads plugin, captures stream-json.
# Usage: run_with_plugin "natural language prompt" [max_turns]
run_with_plugin() {
    local prompt="$1"
    local max_turns="${2:-3}"
    local log
    log=$(mktemp)
    claude -p "$prompt" \
        --model "$TEST_MODEL" \
        --plugin-dir "$PLUGIN_DIR" \
        --dangerously-skip-permissions \
        --max-turns "$max_turns" \
        --verbose \
        --output-format stream-json \
        > "$log" 2>&1
    echo "$log"
}

# Assert output contains pattern.
# Usage: assert_contains "$output" "pattern" "test name"
assert_contains() {
    local output="$1"
    local pattern="$2"
    local name="${3:-test}"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         expected: $pattern"
        echo "         got: $(echo "$output" | head -3)"
        return 1
    fi
}

# Assert output does NOT contain pattern.
assert_not_contains() {
    local output="$1"
    local pattern="$2"
    local name="${3:-test}"
    if echo "$output" | grep -qiE "$pattern"; then
        echo "  [FAIL] $name (pattern found but should not be)"
        echo "         found: $pattern"
        echo "         in: $(echo "$output" | grep -iE "$pattern" | head -1)"
        return 1
    else
        echo "  [PASS] $name"
        return 0
    fi
}

# Assert pattern_a appears before pattern_b in output.
assert_order() {
    local output="$1"
    local pattern_a="$2"
    local pattern_b="$3"
    local name="${4:-order test}"
    local line_a line_b
    line_a=$(echo "$output" | grep -niE "$pattern_a" | head -1 | cut -d: -f1)
    line_b=$(echo "$output" | grep -niE "$pattern_b" | head -1 | cut -d: -f1)
    if [ -n "$line_a" ] && [ -n "$line_b" ] && [ "$line_a" -lt "$line_b" ]; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         expected '$pattern_a' (line $line_a) before '$pattern_b' (line $line_b)"
        return 1
    fi
}

# Assert a skill was triggered in a stream-json log file.
# Usage: assert_skill_triggered "$log_file" "skill-name" "test name"
assert_skill_triggered() {
    local log="$1"
    local skill="$2"
    local name="${3:-skill triggered}"
    local pattern='"skill":"([^"]*:)?'"$skill"'"'
    if grep -q '"name":"Skill"' "$log" && grep -qE "$pattern" "$log"; then
        echo "  [PASS] $name"
        return 0
    else
        echo "  [FAIL] $name"
        echo "         skills that fired: $(grep -o '"skill":"[^"]*"' "$log" | sort -u)"
        return 1
    fi
}

# Assert no tool use happened before the first Skill tool call.
assert_no_premature_work() {
    local log="$1"
    local name="${2:-no premature work}"
    local first_skill_line
    first_skill_line=$(grep -n '"name":"Skill"' "$log" | head -1 | cut -d: -f1)
    if [ -z "$first_skill_line" ]; then
        echo "  [FAIL] $name (skill never called)"
        return 1
    fi
    local premature
    premature=$(head -n "$first_skill_line" "$log" | \
        grep '"type":"tool_use"' | \
        grep -v '"name":"Skill"' | \
        grep -v '"name":"TodoWrite"')
    if [ -n "$premature" ]; then
        echo "  [FAIL] $name"
        echo "         tool use before skill load: $(echo "$premature" | head -1)"
        return 1
    else
        echo "  [PASS] $name"
        return 0
    fi
}

# Track pass/fail counts across a test file.
PASS=0
FAIL=0
record() {
    local result="$1"
    if [ "$result" -eq 0 ]; then
        PASS=$((PASS + 1))
    else
        FAIL=$((FAIL + 1))
    fi
}

summary() {
    echo ""
    echo "Results: $PASS passed, $FAIL failed"
    [ "$FAIL" -eq 0 ]
}
