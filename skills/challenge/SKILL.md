---
name: challenge
description: "Benchmark debate agents against curated code challenges with known bugs. Use when the user invokes '/autoimprove challenge', asks to 'run challenges', 'benchmark debate agents', or 'test review agents'."
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
# Combine rulings and findings into format score-challenge.sh expects
jq -n --argjson rulings "$JUDGE_RULINGS" --argjson findings "$ENTHUSIAST_FINDINGS" \
  '{rulings: $rulings, findings: $findings}' > /tmp/debate-output.json

# Score
scripts/score-challenge.sh challenges/{id}/answer-key.json /tmp/debate-output.json
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
