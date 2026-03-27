---
name: review
description: "Run an adversarial debate review on code. Use when the user invokes '/autoimprove review', asks to 'review code with debate agents', 'run debate review', or 'adversarial review'. Takes a file, diff, or PR as target."
argument-hint: "[file|diff] [--rounds N] [--single-pass]"
allowed-tools: [Read, Glob, Grep, Bash, Agent]
---

Run the Enthusiast → Adversary → Judge debate cycle on the given target.

---

# 1. Parse Arguments

From the user's input, extract:
- **target**: file path, glob pattern, or "diff" (meaning staged/unstaged git diff)
- **rounds**: number of debate rounds (default: auto-scale based on target size)
- **single_pass**: if true, set rounds to 1

If `--single-pass` was passed, set rounds to 1.

If no explicit `--rounds N`, auto-scale:
- Target < 50 lines → 1 round
- Target < 200 lines or ≤ 5 files → 2 rounds
- Target > 200 lines or > 5 files → 3 rounds

---

# 2. Gather Target Code

Read the target code into a variable to pass to agents.

**If target is a file path or glob:**
Read the file(s) using Read tool. Concatenate with file headers.

**If target is "diff":**
```bash
git diff HEAD
```
If empty, try `git diff --staged`. If still empty, tell the user there's nothing to review.

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

Parse the Enthusiast's JSON output. Store as `ENTHUSIAST_OUTPUT`.

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

Parse the Adversary's JSON output. Store as `ADVERSARY_OUTPUT`.

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

Parse the Judge's JSON output. Store as `JUDGE_OUTPUT`.

## 3d. Check Convergence

If the Judge set `convergence: true`, stop the loop early. Record `converged_at_round`.

## 3e. Store Round

Accumulate round results into `ROUNDS` array.

---

# 4. Format Output

After all rounds complete, present results to the user:

```
## Debate Review — {target} ({total_rounds} round(s))

### Confirmed Findings

{For each finding where judge ruled winner=enthusiast or winner=split:}
- **{severity}** [{file}:{line}] {resolution}

### Debunked Findings

{For each finding where judge ruled winner=adversary:}
- ~~{description}~~ — {adversary reasoning}

### Summary

{Judge's final summary}
{If converged: "Debate converged at round {N}."}
```

Also output the full structured JSON so it can be consumed programmatically.

---

# 5. Notes

- Each agent is spawned with `model: sonnet` for cost efficiency.
- The review skill NEVER influences keep/discard decisions in the autoimprove loop. It is advisory only.
- Total token budget: the orchestrator should track approximate token usage. If approaching session limits, warn the user.
