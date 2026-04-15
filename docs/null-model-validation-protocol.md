# Null-Model Validation of Idea-Matrix — Preregistered Protocol

**Registered:** 2026-04-16 (pre-execution)
**Status:** awaiting execution
**Budget estimate:** ~$3, 2-3h
**Motivation:** Codex round-2 adversarial review identified "absence of null model" as the single strongest objection to the 11 lessons from 2026-04-15 matrix experiments. Without a calibrated baseline of how often prompts of this shape converge on "hook-based", "passive-pull", or "neutral cluster" patterns by geometry alone, ≥50% of L5–L11 could be artifact rather than signal extracted by the matrix.

This document preregisters the design BEFORE execution. Any deviation during the run must be logged as a protocol amendment, not silently corrected.

---

## 1. Hypotheses Under Test

Every hypothesis below is explicit, directional, and has a pre-committed rejection threshold. If any hypothesis fails its threshold, the corresponding lesson is downgraded or retracted.

**H1 (L5a validity):** For a given problem domain, the mechanism-category of the matrix winner is stable across neutrally-framed reruns.
- Test: ≥9/12 neutral reruns per domain produce the same pre-registered mechanism category for the winner cell.
- Applies to: L5a ("winner-by-mechanism-category = ship").

**H2 (inter-model independence):** Sonnet and Opus do not merely reproduce Haiku's winner — they identify it independently, including cases where Haiku has convention drift.
- Test: top-2 cells by Haiku composite persist in the top-2 by Sonnet composite AND Opus composite, in ≥2 of 3 domains.
- Applies to: L3 ("cross-model check").

**H3 (mechanism category is not uniform):** The empirical distribution of winning categories across 36 reruns is not consistent with uniform draw from the 4-category space.
- Test: exact multinomial goodness-of-fit against uniform, p < 0.05.
- Applies to: L5a, L10 ("neutral cluster is signal").

**H4 (framing-dependence is the modal outcome, not teatro):** When we run the post-matrix falsification step (L11) on neutral reruns, the verdict distribution is not dominated by `framing_dependent` (>70% would suggest the test does not discriminate).
- Test: across 36 reruns, verdict distribution across {strong, framing_dependent, falsified} is not concentrated on a single bucket at >70%.
- Applies to: L11 ("post-matrix falsification is mandatory").

**H5 (null):** The matrix extracts structure beyond the geometry of the answer manifold.
- Test: on a synthetic control problem with an intentionally flat option landscape (see §6), the matrix should NOT produce consistent winners. If it does, the method is generating winners from prompt structure alone.
- Applies to: meta-critique (Codex Q4).

---

## 2. Domains (3 pre-registered, non-CC, non-magi)

Chosen to maximize mechanism diversity and resist domain-specific confirmation bias. Each domain has a pre-committed mechanism-category set of size 4.

### Domain D1: Caching strategy for a read-heavy web service

**Options presented to matrix:**
- A: In-process LRU cache per instance
- B: Shared Redis cluster
- C: Read-replica database with connection pooling

**Pre-registered mechanism categories (mutually exclusive, collectively cover the space):**
- `local-memory` — no network, no shared state, lives in process memory
- `network-shared` — separate process, networked, multi-instance coherent
- `persistent-disk` — durable store on local or SAN disk
- `compute-derived` — recompute on demand with memoization, no explicit cache

**Tokens banned from neutral reruns (forbidden in cell prompt):**
`redis`, `memcached`, `lru`, `cdn`, `cache`, `ttl`, `eviction`, `invalidation`, any product names.

### Domain D2: Schema migration on a 50M-row production table

**Options presented:**
- A: In-place `ALTER TABLE` with lock
- B: Shadow table + atomic rename
- C: Dual-write to old and new columns with async backfill

**Pre-registered mechanism categories:**
- `in-place-mutation` — change the existing table directly
- `shadow-swap` — build the new state alongside, atomically replace
- `dual-write-reconcile` — write to both, reconcile over time, cut over
- `event-reconstruction` — rebuild from an event log or CDC stream

**Tokens banned:**
`flyway`, `liquibase`, `alembic`, `rails migration`, `ghost`, `pt-online-schema-change`, any specific tooling names.

### Domain D3: Retry strategy for flaky external API

**Options presented:**
- A: Exponential backoff with jitter
- B: Circuit breaker with half-open probe
- C: Dead-letter queue with manual replay

**Pre-registered mechanism categories:**
- `time-based` — waits a computed duration, retries
- `state-based` — tracks failure rate, adjusts behavior conditionally
- `delegation` — offloads the decision to a later actor (human, batch job)
- `redundancy` — calls multiple endpoints or fallbacks in parallel

**Tokens banned:**
`tenacity`, `retry`, `backoff`, `circuit`, `hystrix`, `resilience`, `polly`.

---

## 3. Neutral Prompt Construction

Every rerun uses a neutral cell prompt derived from a template. No hints about the "correct" mechanism, no architectural nudges, no banned tokens.

```
You are scoring a design option for the following problem.

## Problem
{PROBLEM} — one paragraph, describes constraints without naming mechanisms.

## Option Under Evaluation
{OPTION_DESCRIPTION} — one paragraph, describes what the option does without
citing the mechanism categories or banned tokens.

## Score (0-10 each, higher=better)
- feasibility: how hard is this to build correctly
- risk: robustness under failure (higher = safer)
- synergy_potential: composes cleanly with future work
- implementation_cost: low cost to ship (higher = cheaper)

## Also return
- mechanism_novelty: one sentence naming what this option does that others do not
- dealbreaker: flag true/false with one sentence if true

Return JSON only.
```

The cell 8 (remix) and cell 9 (contrarian) prompts get no mechanism hint. They receive:

*Cell 8 neutral:* `Propose a hybrid combining the strongest elements of A, B, C. Score your proposal. Do not reference any specific mechanism by name.`

*Cell 9 neutral:* `Challenge the framing. Propose a fundamentally different approach none of A, B, C explored. Do not reference any specific mechanism by name.`

**Banned-token enforcement:** before dispatch, regex-scan the final prompt text for banned tokens from the domain's list. Any hit = protocol violation, abort and reconstruct.

---

## 4. Execution Plan

**Per domain (12 reruns):**
- 9 reruns with Haiku, `allowed-tools: []`, temperature default.
- 2 reruns with Sonnet (top-2 cells by Haiku composite only, to validate H2).
- 1 rerun with Opus (same top-2 cells).

**Total dispatches:** 3 domains × 12 reruns × 9 cells (partial for Sonnet/Opus) = ~120–150 agent calls.

**Parallelism:** max 9 parallel per dispatch batch, per CC concurrency limits.

**Output schema:** every rerun writes to `experiments/null-model-2026-04-16/runs/D{1,2,3}-rerun-{01..12}.json`:

```json
{
  "domain": "D1",
  "rerun_id": 7,
  "model": "haiku",
  "cells": [
    {
      "cell": 1,
      "label": "A",
      "composite": 6.8,
      "scores": {...},
      "mechanism_novelty": "<verbatim string from agent>",
      "dealbreaker": null,
      "risk_direction_used": "higher_safer"
    },
    ...
  ],
  "winner_cell": 4,
  "winner_mechanism_novelty_raw": "<verbatim string>"
}
```

---

## 5. Blind Coding (Mechanism Category Classification)

The classification of `mechanism_novelty` strings into pre-registered categories MUST be blind to (a) which rerun, (b) which cell, (c) which model generated the string.

**Procedure:**
1. After all reruns complete, extract every `winner_mechanism_novelty_raw` string into `coding-input.tsv` — one row per rerun, columns `coding_id | text`. No rerun_id, no model, no cell.
2. Shuffle the rows.
3. Dispatch a single Haiku judge with the full category taxonomy and the shuffled list. Prompt:
   ```
   For each mechanism string below, assign ONE category from the list {<4 categories for
   the correct domain>}. If the string does not fit any category, return "other". Do not
   infer from context; classify each string independently from the others.
   Return JSON: [{coding_id: N, category: "<label>"}].
   ```
4. Dispatch a parallel Sonnet judge with identical input — the two classifications are compared for inter-judge agreement (Cohen's kappa). Disagreements are resolved by a third Opus judge.
5. The resolved classifications are merged back to the run records for analysis.

**Agreement threshold:** if Cohen's kappa between Haiku and Sonnet judges is < 0.6, the classification task is too ambiguous and the domain is dropped from H1 analysis. This protects against false positives from judge noise.

---

## 6. Synthetic Control (H5)

A 4th "flat" domain is run with options designed to be genuinely interchangeable. The purpose is to establish the null: if the matrix produces consistent winners here, it is extracting structure from prompt geometry rather than from option content.

**Domain D0 (synthetic flat):**
- A: Deploy on weekday mornings
- B: Deploy on weekday afternoons
- C: Deploy on weekday evenings

No real trade-offs exist beyond taste. If matrix reruns on D0 produce a stable winning category in ≥9/12 reruns, then H5 is falsified — the matrix is generating signal from prompt shape regardless of content. In that case, H1/H2/H3 cannot be defended even if they pass, because their pass could share the same artifact.

Budget: D0 adds ~$0.30 to the total.

---

## 7. Analysis

Post-execution, run `experiments/null-model-2026-04-16/analyze.py` (to be written at run time, scaffold below). Pre-committed analysis:

- **For H1:** per domain, count how many of 12 reruns have a winner classified into the same category as the modal category. Pass if count ≥ 9.
- **For H2:** for each domain, take top-2 Haiku cells by composite. Check Sonnet top-2 and Opus top-2. Pass if ≥2 of 3 domains have ≥1 overlap in both model comparisons.
- **For H3:** chi-squared or exact multinomial of winner-category distribution vs uniform (1/4, 1/4, 1/4, 1/4) per domain. Pass if p < 0.05 for ≥2 of 3 domains.
- **For H4:** run post-matrix falsification (L11) on the 3 modal winners (one per domain). Classify verdicts. Pass if no single verdict type > 70%.
- **For H5:** count D0 reruns with modal category winner. Fail if count ≥ 9.

All analysis code is written AFTER reruns complete, to prevent p-hacking through analysis choice. The hypothesis thresholds above are frozen as of 2026-04-16.

---

## 8. Protocol Amendments

Any change to this document after 2026-04-16 execution start must:
1. Append a dated "Amendment" section below.
2. Justify the change.
3. Note which hypothesis interpretation it affects.

No amendments yet.

---

## 9. Expected Deliverable

After execution, produce `experiments/null-model-2026-04-16/REPORT.md`:

- H1/H2/H3/H4/H5 pass/fail table with numbers.
- Per-lesson decision: which of L1–L11 are supported, downgraded, or retracted.
- Updated idea-matrix skill PR (if any) linked for re-review.
- Codex round-3 adversarial review invitation — give Codex the full data and let it challenge.

Budget for report + codex round 3: ~$1 extra.

---

## 10. Abort Conditions

Protocol aborts mid-run if:
- Any domain exceeds 2× its budget estimate (cost check at rerun 6 of 12).
- Banned-token scan trips more than once per domain (signals the prompts cannot be neutralized for this domain).
- Inter-judge kappa < 0.6 on coding (see §5) — domain is dropped rather than fixed post-hoc.

On abort, write `experiments/null-model-2026-04-16/ABORT.md` with the trigger and partial data. Do not try to salvage ambiguous results.
