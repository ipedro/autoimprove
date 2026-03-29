#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

# test_count: number of test cases in the evaluate.sh test suite
# Marker format: echo "--- Test: <name> ---"
if [ -f "$DIR/test/evaluate/test-evaluate.sh" ]; then
  test_count=$(grep -c -- "--- Test:" "$DIR/test/evaluate/test-evaluate.sh" 2>/dev/null || true)
else
  test_count=0
fi

# broken_constraints: load-bearing invariant phrases must remain in experimenter agent
broken_constraints=0
for phrase in "forbidden_paths" "additive only" "how your changes are scored" "worktree"; do
  grep -q "$phrase" "$DIR/agents/experimenter.md" 2>/dev/null || broken_constraints=$((broken_constraints + 1)) || true
done
# Line-count floor: catches wholesale file gutting
if [ -f "$DIR/agents/experimenter.md" ]; then
  lines=$(wc -l < "$DIR/agents/experimenter.md")
else
  lines=0
fi
[ "$lines" -lt 20 ] && { broken_constraints=$((broken_constraints + 1)) || true; }

# broken_refs: critical files referenced by the orchestrator must exist
broken_refs=0
for f in \
  "$DIR/skills/run/references/loop.md" \
  "$DIR/agents/experimenter.md" \
  "$DIR/scripts/evaluate.sh"; do
  [ -f "$f" ] || broken_refs=$((broken_refs + 1)) || true
done

# skill_doc_coverage: number of skills with a non-empty description in SKILL.md
skill_doc_coverage=0
for skill_dir in "$DIR/skills"/*/; do
  if [ -f "$skill_dir/SKILL.md" ]; then
    grep -q "^description:" "$skill_dir/SKILL.md" 2>/dev/null && skill_doc_coverage=$((skill_doc_coverage + 1)) || true
  fi
done

# agent_completeness: number of agents with both name and description fields
agent_completeness=0
for agent_file in "$DIR/agents"/*.md; do
  [ -f "$agent_file" ] || continue
  if grep -q "^name:" "$agent_file" 2>/dev/null && grep -q "^description:" "$agent_file" 2>/dev/null; then
    agent_completeness=$((agent_completeness + 1))
  fi
done

echo "{\"test_count\": $test_count, \"broken_constraints\": $broken_constraints, \"broken_refs\": $broken_refs, \"skill_doc_coverage\": $skill_doc_coverage, \"agent_completeness\": $agent_completeness}"
