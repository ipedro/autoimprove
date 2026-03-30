#!/bin/bash
# benchmark/matrix-effectiveness.sh
# Measures idea-matrix skill quality on golden problem: "How to improve grind loop theme targeting"
# Metrics: cell_depth, convergence_quality, option_diversity

set -euo pipefail

# Check if claude CLI is available
if ! command -v claude &> /dev/null; then
  echo '{"matrix_cell_depth": -1, "matrix_convergence_quality": -1, "matrix_option_diversity": -1, "error": "claude CLI not found"}'
  exit 1
fi

# Temporary file for matrix output
MATRIX_OUTPUT=$(mktemp)
trap "rm -f $MATRIX_OUTPUT" EXIT

# Step 1: Run idea-matrix on golden problem statement
echo "[*] Running idea-matrix on golden problem..."
claude --print --model haiku -p "Run idea matrix on this problem: How to improve grind loop theme targeting. Options: (A) golden test cases, (B) LLM judge, (C) self-referential, (D) comparative diff. Output a structured evaluation matrix and a convergence report picking the winner." 2>/dev/null > "$MATRIX_OUTPUT" || true

# Check if output was generated
if [ ! -s "$MATRIX_OUTPUT" ]; then
  echo '{"matrix_cell_depth": -1, "matrix_convergence_quality": -1, "matrix_option_diversity": -1, "error": "no output from claude CLI"}'
  exit 1
fi

# Step 2: Extract metric 1 - matrix_cell_depth (avg words per cell)
WORD_COUNT=$(wc -w < "$MATRIX_OUTPUT")
# Guard against division by zero
if [ "$WORD_COUNT" -eq 0 ]; then
  MATRIX_CELL_DEPTH=0
else
  # Approximate 9 cells for 3x3 matrix
  MATRIX_CELL_DEPTH=$((WORD_COUNT / 9))
fi

# Step 3: Extract metric 2 - matrix_convergence_quality
# Score 1 if known-good answer (A+C or golden+self) appears, 0 otherwise
if grep -qi "A+C\|A and C\|golden.*self\|self.*golden" "$MATRIX_OUTPUT" 2>/dev/null; then
  MATRIX_CONVERGENCE_QUALITY=1
else
  MATRIX_CONVERGENCE_QUALITY=0
fi

# Step 4: Extract metric 3 - matrix_option_diversity
# Count distinct option labels (A, B, C, D)
MATRIX_OPTION_DIVERSITY=$(grep -oE '\b[ABCD]\b' "$MATRIX_OUTPUT" 2>/dev/null | sort -u | wc -l | tr -d ' ')

# Output JSON
echo "{\"matrix_cell_depth\": $MATRIX_CELL_DEPTH, \"matrix_convergence_quality\": $MATRIX_CONVERGENCE_QUALITY, \"matrix_option_diversity\": $MATRIX_OPTION_DIVERSITY}"
