---
name: adversarial-review
description: "Run an adversarial Enthusiast→Adversary→Judge debate review on code. Use when the user says 'adversarial review', 'debate review', 'run a review round', 'do a review round', 'review code with debate agents', 'i want an adversarial review', or '/autoimprove review'. Do NOT trigger on generic 'review' requests or PR reviews. Takes a file, diff, or PR as target."
argument-hint: "[file|diff] [--rounds N] [--single-pass]"
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

<SKILL-GUARD>
You are NOW executing the adversarial-review skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly. Invoking it again would create an infinite loop.
</SKILL-GUARD>

Run the Enthusiast → Adversary → Judge debate cycle on the given target.

---

# 1. Parse Arguments

From the user's input, extract:
- **target**: file path, glob pattern, or "diff" (meaning staged/unstaged git diff)
- **rounds**: number of debate rounds (default: auto-scale based on target size)
- **single_pass**: if true, set rounds to 1

If `--single-pass` was passed, set rounds to 1.

If `--rounds N` was explicitly passed, use N (minimum 1). User-specified rounds always take precedence over auto-scale.

If the user requests fewer rounds without `--rounds` (e.g. "quick review", "just one pass"), reduce the auto-scaled value by 1, minimum 1. Log: `"User requested quick review — rounds reduced to <N>"`.

If no explicit round count or quick-review request, auto-scale based on target size:
- More than 5 files OR 200+ lines → 3 rounds
- 50–199 lines (and ≤ 5 files) → 2 rounds
- Fewer than 50 lines (and ≤ 5 files) → 1 round

(File count takes precedence over line count when both thresholds trigger.)

---

# 2. Gather Target Code

Read the target code into a variable to pass to agents.

**If target is a file path or glob:**
Read the file(s) using Read tool. Concatenate with file headers.

**If target is "diff":**
```bash
git diff HEAD
```
If empty, try `git diff --staged`. If still empty, tell the user: "Nothing to review — both working tree and staging area are clean. Try: `git diff <branch>`, `git diff HEAD~1`, `/autoimprove review <file>`, or stage some changes first."

Store the result as `TARGET_CODE`.

---

# 3. Run Debate Rounds

For each round (1 to N):

## 3a. Spawn Enthusiast

Use the Agent tool to spawn the `enthusiast` agent:

```
Prompt: Review the following code and find all issues.

<code>
{TARGET_CODE}
</code>

{If round > 1: "Prior round findings and rulings: {PRIOR_ROUND_OUTPUT}. Focus on what was MISSED — do not repeat prior findings."}

Output your findings as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Enthusiast's response as JSON.
- If valid JSON with a non-empty `findings` array → store as `ENTHUSIAST_OUTPUT` and continue.
- If invalid JSON → re-prompt once: `"Your previous response was not valid JSON. Return only the corrected JSON object — no prose, no markdown fences."` Re-parse. If still invalid → log `enthusiast_malformed_json` for this round, skip to next round (or abort if only round).
- If valid JSON but `findings` is empty → note "Enthusiast found no issues" and skip 3b/3c for this round; proceed to 3e.

## 3b. Spawn Adversary

Use the Agent tool to spawn the `adversary` agent:

```
Prompt: Review the Enthusiast's findings and challenge them.

<code>
{TARGET_CODE}
</code>

<findings>
{ENTHUSIAST_OUTPUT}
</findings>

Output your verdicts as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Adversary's response as JSON.
- If valid JSON with a `verdicts` array → store as `ADVERSARY_OUTPUT` and continue.
- If invalid JSON → re-prompt once with the same correction instruction. If still invalid → log `adversary_malformed_json`, pass `{"verdicts": []}` as the adversary input to the Judge (all findings treated as uncontested via Judge's missing-verdicts edge case).

## 3c. Spawn Judge

Use the Agent tool to spawn the `judge` agent:

```
Prompt: Arbitrate between the Enthusiast and Adversary.

<code>
{TARGET_CODE}
</code>

<findings>
{ENTHUSIAST_OUTPUT}
</findings>

<verdicts>
{ADVERSARY_OUTPUT}
</verdicts>

{If round > 1: "Your prior round rulings: {PRIOR_JUDGE_OUTPUT}. Set convergence: true if your rulings this round are identical to last round."}

Output your rulings as a single JSON object matching the schema. Nothing else.
```

**Validate output**: Parse the Judge's response as JSON.
- If valid JSON with a `rulings` array → store as `JUDGE_OUTPUT` and continue.
- If invalid JSON → re-prompt once. If still invalid → log `judge_malformed_json`, record all findings as `status: unresolved`, and end the debate loop.

## 3d. Check Convergence

Convergence is only meaningful from round 2 onward.

**Deterministic check (orchestrator-side):** When `round > 1`, compute convergence independently by comparing this round's rulings to the prior round's rulings:
- Extract the set of `(finding_id, winner, final_severity)` tuples from both rounds
- If the sets are identical (same IDs, same winners, same severities in any order) → `converged = true`
- This overrides whatever the Judge reported

**LLM check (supplemental):** Also check what the Judge reported. If Judge says `convergence: true` but the deterministic check says `false`, log: `"Judge reported convergence but rulings differ — continuing."` and continue.

**Round 1 guard:** If `round == 1` and Judge returned `convergence: true` → treat as `false`. Log: `"convergence: true ignored on round 1."` Continue to round 2.

**Stop condition:** Stop the loop early when `converged = true` (deterministic). Record `converged_at_round = round`.

## 3e. Store Round

Accumulate round results into `ROUNDS` array.

---

# 4. Format Output

After all rounds complete, present results to the user:

```
## Debate Review — {target} ({total_rounds} round(s){if converged: ", converged at round N"})

### Confirmed Findings

{For each finding where judge ruled winner=enthusiast or winner=split:}
- **{severity}** [{file}:{line}] {resolution}

### Debunked Findings

{For each finding where judge ruled winner=adversary:}
- ~~{description}~~ — {adversary reasoning}

### Unresolved Findings

{If any findings have status: unresolved (judge_malformed_json occurred):}
- **{severity}** [{file}:{line}] {description} *(unresolved — judge output was malformed)*

{If no unresolved findings: omit this section entirely}

### Summary

{Judge's final summary}
{If converged: "Debate converged at round {N}."}
{If any malformed_json errors: "Warning: {N} round(s) had agent output errors — results may be incomplete."}
```

Also output the full structured JSON so it can be consumed programmatically.

---

# 5. Notes

- Each agent is spawned with `model: sonnet` for cost efficiency.
- The review skill NEVER influences keep/discard decisions in the autoimprove loop. It is advisory only.
- Total token budget: the orchestrator should track approximate token usage. If approaching session limits, warn the user.
