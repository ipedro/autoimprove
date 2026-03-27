---
name: challenge
description: "Use when testing debate agent bug-finding accuracy against curated code challenges — F1 scoring, 'test debate agents on challenges', 'benchmark agents'. Examples:

<example>
Context: User wants to measure how accurately agents find bugs.
user: \"test debate agents on the challenge suite\"
assistant: I'll use the challenge skill to score agents with F1 metrics.
<commentary>Testing agent accuracy — challenge skill, not prompt-testing.</commentary>
</example>

<example>
Context: User wants F1 scores on a language subset.
user: \"benchmark agents on python challenges\"
assistant: I'll use the challenge skill to score agents on the Python suite.
<commentary>Benchmarking with filter — challenge skill.</commentary>
</example>

Do NOT use for writing tests for skills/agents (use prompt-testing instead)."
argument-hint: "[--suite puzzles|all] [--language python|typescript|go|rust|all]"
allowed-tools: [Read, Bash, Glob, Grep, Agent]
---

Run debate agents against curated challenges and score them with precision-weighted F1.

---

# 1. Parse Arguments

- **suite**: "puzzles" (default) or "all"
- **language**: filter to a specific language, or "all" (default)

---

# 2. Load Manifest

Read `challenges/manifest.json` from the project root.

Filter challenges by the `language` argument if specified.

Report how many challenges will be run:
```
Running {N} challenges ({languages})...
```

---

# 3. Run Each Challenge

For each challenge in the filtered manifest:

## 3a. Read Challenge Code

Read the challenge file (e.g., `challenges/python/off-by-one/challenge.py`).

The file extension tells you the language:
- `.py` → Python
- `.ts` → TypeScript
- `.go` → Go
- `.rs` → Rust

## 3b. Run Single-Pass Review

Run the review skill in single-pass mode (1 round) on the challenge file. This spawns:
1. Enthusiast agent → finds issues
2. Adversary agent → challenges findings
3. Judge agent → renders verdicts

Capture the structured JSON output from the debate.

## 3c. Score Against Answer Key

Prepare a combined JSON file with the Judge's rulings AND the Enthusiast's findings (the scoring script needs both to match file/line/type):

```bash
# Write components via printf to avoid shell injection on embedded quotes (F5)
# Use mktemp to prevent parallel-run collisions (F6)
debate_tmpfile=$(mktemp /tmp/debate-output-XXXXXX.json)
rulings_tmpfile=$(mktemp /tmp/debate-rulings-XXXXXX.json)
findings_tmpfile=$(mktemp /tmp/debate-findings-XXXXXX.json)
printf '%s' "${JUDGE_RULINGS}" > "$rulings_tmpfile"
printf '%s' "${ENTHUSIAST_FINDINGS}" > "$findings_tmpfile"
jq -n \
  --slurpfile rulings "$rulings_tmpfile" \
  --slurpfile findings "$findings_tmpfile" \
  '{rulings: $rulings[0], findings: $findings[0]}' > "$debate_tmpfile"
rm "$rulings_tmpfile" "$findings_tmpfile"

# Use absolute path relative to project root (F7)
SCORE_SCRIPT="$(git rev-parse --show-toplevel)/scripts/score-challenge.sh"
ANSWER_KEY="$(git rev-parse --show-toplevel)/challenges/{id}/answer-key.json"
"$SCORE_SCRIPT" "$ANSWER_KEY" "$debate_tmpfile"
rm "$debate_tmpfile"
```

Parse the F1 score from the output JSON.

## 3d. Report Result

Print per-challenge result:
```
  {id}: F1={f1} (P={precision} R={recall}) TP={tp} FP={fp} FN={fn} {PASS|FAIL}
```

---

# 4. Aggregate and Report

After all challenges complete:

```
## Challenge Results

| Challenge | Language | F1 | Precision | Recall | Verdict |
|---|---|---|---|---|---|
| python/off-by-one | python | 1.00 | 1.00 | 1.00 | PASS |
| python/null-handling | python | 0.80 | 0.67 | 1.00 | PASS |
| ... | ... | ... | ... | ... | ... |

**Overall: {passed}/{total} passed (avg F1: {avg_f1})**
```

---

# 5. Log Results

Append a summary line to `experiments.tsv` (if it exists) with `type: challenge`:

```
{id}	{timestamp}	challenge	-	{total_challenges}	{avg_f1}	-	-	{pass_count}/{total}	{tokens_used}	{wall_time}	Challenge benchmark: {passed}/{total} passed
```

This enables longitudinal tracking of agent accuracy over time.
