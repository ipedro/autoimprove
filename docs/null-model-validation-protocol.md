# Null-Model Validation of Idea-Matrix — Preregistered Protocol

**Version:** 5.0 (2026-04-16)
**Status:** awaiting execution (budget-gated to post-reset)
**Budget estimate:** ~$8-9, 3-5h
**Previous versions:**
- v1 (commit c6245ad) — rejected in Codex round-3.
- v2 (commit c9ffd33) — addressed round-3 but predated autoimprove#105.
- v3 (commit 25b35e4) — addressed #105; rejected in round-4.
- v4 (commit 478e861) — addressed round-4. Codex round-5 identified three more execution-blocking issues: (a) H2 ran only the Haiku modal-winner cell against Sonnet/Opus, so the test could not actually measure "same winner across models" — Sonnet might rank one of the 7 untested cells higher; (b) H6 conformance formula `ok / (total − dropped)` excluded drops from the denominator, masking widespread failure; (c) main 9-cell reruns with exactly 1 dropped cell survived without specified semantics, leaving post-hoc analyst discretion.

v5 addresses all three. Changes summarized in §11.

**Motivation:** Codex round-2 adversarial review identified "absence of null model" as the single strongest objection to the 11 lessons from 2026-04-15 matrix experiments. Issue #105 added two more: scoring discipline cannot be enforced by prompt alone; evaluation without codebase infrastructure context produces false dealbreakers. A validation protocol that ignores either is itself invalid.

This document preregisters the design BEFORE execution. Any deviation must be logged as a protocol amendment — see §8.

---

## 1. Hypotheses Under Test

Each hypothesis has (a) a single pre-committed statistical test, (b) a single pre-committed threshold, (c) a dependency on schema enforcement (§3.1) succeeding. §7 mirrors these definitions literally.

**H1 (L5a validity):** For a given problem domain, the mechanism-category of the matrix winner is stable across neutrally-framed reruns.
- **Test:** for each domain, count reruns where winner's `mechanism_novelty` is blind-classified (§5) into the pre-registered target category.
- **Threshold:** ≥14/20 in the target category for ≥2 of 3 real domains (D1, D2, D3).
- **Prerequisite:** schema-conformance rate (§3.1) ≥ 80% for that domain. Below that, H1 is declared FAILED for the domain (not dropped — prompt-only discipline is itself what L5a would rely on in practice).

**H2 (inter-model winner-identity agreement):** Sonnet and Opus identify the same winning *cell* as Haiku under the same blind neutral prompt.
- **Test:** for each real domain, dispatch a full 9-cell grid for Sonnet (×3 reruns) and for Opus (×3 reruns). For each model, take the modal winner cell across its 3 reruns. Compare to the Haiku modal winner cell.
- **Threshold:** Sonnet modal winner == Haiku modal winner AND Opus modal winner == Haiku modal winner, for ≥2 of 3 real domains.
- **v5 honesty note:** v3-v4 used a single-cell rerun design that could not actually test winner identity (Sonnet might rank one of the 7 untested cells higher). v5 runs the full grid. Cost: +~$1.50 for the extra 6 × 9 = 54 Sonnet+Opus dispatches per domain × 3 domains = 162 dispatches.

**H3 (mechanism category is not uniform):** Empirical distribution of blind-classified winning categories is not consistent with uniform 1/4 draw.
- **Test:** exact binomial (scipy.stats.binomtest) on target-category frequency vs p₀=0.25, one test per real domain.
- **Threshold:** p < 0.0125 (Bonferroni-corrected, 4 tests) for ≥2 of 3 real domains.

**H4 (post-matrix falsification discriminates):** L11 falsification on modal winners of D1/D2/D3 produces non-degenerate verdict distribution.
- **Test:** classify 3 verdicts as {strong, framing_dependent, falsified}; count.
- **Threshold:** no single verdict accounts for all 3.
- **Honesty note:** underpowered — sanity check, not validation.

**H5 (null — matrix does not fabricate structure):** On synthetic flat D0, matrix should NOT produce dominant winner category.
- **Test:** exact binomial on D0 target-category frequency vs p₀=0.25.
- **Threshold:** p ≥ 0.0125 (FAIL-to-reject uniformity). If D0 shows p<0.0125, H5 is falsified and D1/D2/D3 positive results lose standing.

**H6 (schema discipline) — NEW in v3:** With schema enforcement (§3.1), cell outputs conform to the prescribed 4-dimension rubric at a rate high enough for composites to be comparable.
- **Test:** compute `schema_conformance_rate = cells_with_exact_4_dims / total_cells` per domain, over all 20 reruns × 9 cells × 4 domains = 720 cell outputs.
- **Threshold:** rate ≥ 80% per domain, in all 4 domains. One domain below 80% triggers H6 failure.
- **Applies to:** L7 (the issue #105 finding that prompt-only discipline drifts).
- **Consequence of H6 failure:** if H6 fails, H1 and H3 for that domain are automatically declared FAILED (composites are not comparable when dimensions drift).

### Power Analysis (Justifying n=20 and threshold 14/20)

Under H0 (uniform 4-category, p=0.25), P(X≥14/20) = 0.00014. Bonferroni-corrected for 4 categories: ~5.5e-4. Well below α=0.01.

Under H1 true p=0.70 (modest effect), power ≈ 0.58. Under p=0.85 (strong effect), power ≈ 0.93. **Honest limitation:** negative result is consistent with both no-effect and missed-modest-effect. Positive result excludes no-effect with >99% confidence.

---

## 2. Domains (3 real + 1 synthetic control, 4 total)

Each domain specifies: 3 options, 4 MEE mechanism categories (single-axis partition — see §2.1), target category prediction, banned tokens, and — new in v3 — an **environment block** (L8 infrastructure context).

### 2.1 MEE Category Design Principle

v1 categories overlapped. v2 fixed by choosing a single axis of differentiation per domain. v3 retains this; each taxonomy is a partition, not a tagset.

### 2.2 Environment Blocks (L8 — New in v3)

Each domain pre-registers a paragraph describing the deployment context. This prevents haiku from hallucinating dealbreakers about infrastructure that is present or absent. The block is part of every cell prompt (§3).

### Domain D1: Caching strategy for a read-heavy web service

**Options:**
- A: In-process LRU cache per instance
- B: Shared Redis cluster
- C: Read-replica database with connection pooling

**Axis:** *Where does the authoritative read-path state live?*
- `in-process-private` — serving process holds its own copy, no coordination (A)
- `out-of-process-shared` — separate coordinating process, networked (B)
- `source-replica` — read-path state is a replica of the system of record (C)
- `recompute-on-demand` — no dedicated cached state

**Target category:** `out-of-process-shared` (B).

**Environment block:**
```
Service runs as 8 stateless replicas behind a load balancer on Kubernetes.
PostgreSQL primary is the system of record (4 vCPU, 16GB, read IOPS at 60% ceiling).
Prometheus + Grafana for metrics. Service mesh (Istio) provides mTLS and retries.
No existing cache infrastructure. Network latency within cluster <1ms p99.
Deploy pipeline rolls replicas 1-at-a-time; no blue/green.
```

**Banned tokens:** `redis`, `memcached`, `lru`, `cdn`, `cache`, `ttl`, `eviction`, `invalidation`, `hazelcast`, `ignite`, product names.

### Domain D2: Schema migration on a 50M-row production table

**Options:**
- A: In-place `ALTER TABLE` with lock
- B: Shadow table + atomic rename
- C: Dual-write to old and new columns with async backfill

**Axis:** *Does the migration hold a write lock during its runtime?*
- `lock-and-mutate` (A)
- `parallel-build-then-swap` (B)
- `incremental-reconcile` (C)
- `rebuild-from-log` — no lock, replay event log

**Target category:** `parallel-build-then-swap` (B).

**Environment block:**
```
Primary PostgreSQL 15, 50M-row table under active write load (~200 writes/sec).
Write downtime tolerance: 5 minutes planned maintenance window max.
Read replicas exist (2 async). Logical replication available.
No CDC pipeline. No event log. Application code controlled by same team.
Rollback SLA: 10 minutes from detection. Customer-facing — errors visible.
```

**Banned tokens:** `flyway`, `liquibase`, `alembic`, `gh-ost`, `pt-online-schema-change`, `rails migration`, `django migration`, tool names.

### Domain D3: Retry strategy for flaky external API

**Options:**
- A: Exponential backoff with jitter
- B: Circuit breaker with half-open probe
- C: Dead-letter queue with manual replay

**Axis:** *What information drives the retry decision?*
- `time-only` (A)
- `failure-rate-state` (B)
- `deferred-delegation` (C)
- `parallel-fallback` — multiple targets concurrently

**Target category:** `failure-rate-state` (B).

**Environment block:**
```
API consumed: third-party payment processor. p99 latency 500ms, failure rate
spikes to 30% during their deploys (weekly, unannounced). No webhook/callback
from them. Our service processes 50 req/sec peak. Idempotency keys are supported.
Redis available for shared state. Ops team on-call 24/7 for P1; P2 batched.
User-facing latency budget 1.5s p95. Failed request cost: blocked checkout.
```

**Banned tokens:** `tenacity`, `retry`, `backoff`, `circuit`, `hystrix`, `resilience4j`, `polly`, `jitter`, library names.

### Domain D0 (synthetic control): Deploy window choice

**Options:**
- A: Deploy on weekday mornings
- B: Deploy on weekday afternoons
- C: Deploy on weekday evenings

**Axis:** time-of-day.
- `morning`
- `afternoon`
- `evening`
- `other` (night/weekend/never)

**Target category:** NONE — we predict no signal.

**Environment block:**
```
Team is 8 engineers in a single time zone. No external SLAs tied to deploy windows.
CI takes 12 minutes. Rollback takes 3 minutes. No global traffic patterns worth
mentioning — traffic distribution across the day is flat within 10%.
No users report time-of-day preferences.
```
(Deliberately flat — every window is equivalent.)

**Banned tokens:** `standup`, `lunch`, `traffic`, `on-call`, `monitoring`, `rollback`.

---

## 3. Neutral Prompt Construction

Each cell prompt is constructed from a template with two neutrality gates and one schema gate:

**Lexical gate (automated):** regex scan **the model's output text**, NOT the prompt. The prompt's pre-registered environment block (§2.2) may contain neutral mentions of vocabulary that overlaps the banned-token list (e.g., D1's environment notes "no existing cache infrastructure" while `cache` is banned in model output). This is intentional — the goal is to prevent the model from re-introducing banned terms in `mechanism_novelty` and `dealbreaker`, not to censor the deployment context. Output hit = re-dispatch (per §3.1 schema procedure).

**Conceptual gate (human):** Pedro reads the ~12 unique prompt bodies (cells share prefixes) and rejects on paraphrased leakage. ~5 min per domain.

**Schema gate (automated, new in v3):** after dispatch, each cell output is JSON-parsed and validated for exact 4-dimension schema, score type/bounds, composite integrity, and dealbreaker grounding (§3.1).

**Cell template (Haiku):**
```
CRITICAL: Do NOT invoke any tools. Answer only from this prompt. Return JSON immediately.

You are scoring a design option for the following problem.

## Problem
{PROBLEM}

## Available Infrastructure / Environment
{ENVIRONMENT_BLOCK}

## All Options Under Consideration
A: {A_description}
B: {B_description}
C: {C_description}

## Option Under Evaluation
Cell {N}: {LABEL} — {OPTION_DESCRIPTION}

## SCORING CONVENTION (MANDATORY — HIGHER=BETTER on ALL dimensions)

You MUST score EXACTLY these four dimensions, using these EXACT keys. Do not add,
rename, or omit any. Your output will be schema-validated and rejected if the
dimension keys do not match.

- feasibility: 1 showstopper → 10 trivial to build
- risk: 1 highest risk → 10 lowest risk / most robust (HIGHER = SAFER)
- synergy_potential: 1 incompatible → 10 composes cleanly
- implementation_cost: 1 days of work → 10 minutes

## Output (JSON only, no prose, no fences)

{
  "cell": {N},
  "label": "{LABEL}",
  "risk_direction_used": "higher_safer",
  "scores": {
    "feasibility": <int 1-10>,
    "risk": <int 1-10>,
    "synergy_potential": <int 1-10>,
    "implementation_cost": <int 1-10>
  },
  "composite": <mean of the 4 scores>,
  "mechanism_novelty": "<one sentence; no banned tokens; commit to one mechanism, no hedging>",
  "dealbreaker": null or "<one sentence; if risk is based on infrastructure, only cite infrastructure explicitly listed in the Environment block above>"
}

Your "scores" object must contain EXACTLY those 4 keys. Any other keys cause
rejection and re-dispatch. Do not include correctness, complexity, robustness,
token_efficiency, coordination_power, debuggability, failure_isolation,
leverage, novelty, composability, runtime_safety, latency_impact, reliability,
observability_gain, operational_complexity, security_surface, safety,
hook_coverage, or any other dimension. Four dimensions. Named exactly as above.
```

### 3.1 Schema Validation (NEW in v3, hardened in v4 per Codex round-4)

After each rerun batch, every cell output is validated against five gates:

```python
import json, re

REQUIRED = {"feasibility", "risk", "synergy_potential", "implementation_cost"}

def validate(cell_output, env_block_text, banned_tokens):
    # Gate 1: parses
    try:
        obj = json.loads(cell_output)
    except json.JSONDecodeError:
        return "parse_fail"

    # Gate 2: exact 4-key schema
    scores = obj.get("scores", {})
    if set(scores.keys()) != REQUIRED:
        return "schema_fail"

    # Gate 3: convention declared
    if obj.get("risk_direction_used") != "higher_safer":
        return "convention_fail"

    # Gate 4: scores are integers in [1, 10]
    for k, v in scores.items():
        if not isinstance(v, int) or not (1 <= v <= 10):
            return "score_type_fail"

    # Gate 5: composite is recomputed (model-reported value is discarded)
    obj["composite"] = sum(scores.values()) / 4.0

    # Gate 6: lexical scan only on model-generated text fields
    output_text = " ".join([
        obj.get("mechanism_novelty", "") or "",
        obj.get("dealbreaker", "") or "",
    ]).lower()
    for token in banned_tokens:
        if re.search(rf"\b{re.escape(token.lower())}\b", output_text):
            return "banned_token_fail"

    # Gate 7: dealbreaker grounding — if dealbreaker exists and cites
    # infrastructure, the cited infrastructure must appear in the environment
    # block. Heuristic: dealbreaker contains a noun matching some env-block
    # noun, OR the dealbreaker is a generic concern (no infra noun).
    db = (obj.get("dealbreaker") or "").lower()
    if db and _cites_unlisted_infra(db, env_block_text):
        return "infra_grounding_fail"

    return "ok"
```

`_cites_unlisted_infra` is a small Pedro-coded heuristic: extracts noun phrases from the dealbreaker text using a 30-line regex helper, checks each against the environment block text. If any noun phrase names infrastructure (heuristic: ends in `daemon`, `service`, `queue`, `cluster`, `database`, `pipeline`, `mesh`, `cache`, `replica`, etc.) and is NOT in the environment block, the gate fails. The helper code is committed before execution and frozen.

**Enforcement (v5 — single rule for partial drops):**
- Any of the 7 gates fails → re-dispatch that cell ONCE with a stricter preamble that names the specific failure mode.
- Second failure → mark that cell as `dropped` for the rerun.
- **Any rerun with ≥1 dropped cell is invalidated** — the entire rerun is discarded (cells not used in winner counting). This is a hard rule that removes post-hoc discretion about how to score 8-of-9 grids.
- Invalidated reruns count as **9 dropped cells** toward the H6 conformance denominator (see formula below).
- **H2 grids (Sonnet/Opus 9-cell):** same rule — any drop invalidates the whole 3-rerun grid for that model on that domain. Invalidated grid counts as failure to identify a winner; H2 for that domain auto-fails.

**Conformance formula (v5 — denominator is fixed):**
```
schema_conformance_rate = ok_cells / total_dispatched_cells
```
Where `total_dispatched_cells = 9 cells × 20 reruns = 180` per domain (regardless of how many were retried, dropped, or invalidated). A cell that fails twice and is dropped counts as 0 ok-cells. An invalidated rerun's 9 cells all count as 0 ok-cells, even if some were individually `ok` — because the analysis-level rule discards them. This eliminates the v4 bug where excluding drops from the denominator could mask widespread failure.

**H6 consumes this rate.** H1 and H3 are conditional on `schema_conformance_rate ≥ 80%` per domain.

---

## 4. Execution Plan

**Per domain × 4 domains:**
- 20 Haiku reruns × 9 cells, `allowed-tools: []`.

**Plus for H2 (D1, D2, D3 — v5 full grid):**
- 3 Sonnet reruns × 9 cells per domain.
- 3 Opus reruns × 9 cells per domain.

**Total dispatches:**
- 4 × 20 × 9 = 720 Haiku cell dispatches.
- 3 × 2 × 3 × 9 = 162 Sonnet+Opus cell dispatches.
- Schema re-dispatches: estimated 15-25% failure rate → ~150 extra dispatches.
- Blind-coding judges (§5): 12 dispatches.
- **Grand total: ~1,044 dispatches.**

**Budget:** Haiku ~$2.00, Sonnet+Opus ~$3.20, coding ~$0.30, re-dispatches ~$0.50. Total ~$6.00. Add 1.5× buffer: **$8-9**.

**Wall clock:** ~2h with parallelism (9 cells parallel, 20 reruns per domain, 4 domains).

---

## 5. Blind Coding (v3 — unchanged from v2 but clarified)

Requirements:
1. Two judges from different model families (Haiku + Sonnet).
2. Cohen's kappa ≥ 0.75 threshold — below that, domain H1/H3 declared FAILED (not dropped).
3. Third judge is HUMAN (Pedro) — adjudicates disagreements. Breaks model-family correlation chain.
4. Co-error check in report: human-vs-model-consensus disagreement rate on sampled subset. If > 15%, downgrade H-results with the note "coding may reflect model co-error".

Procedure same as v2 §5.

---

## 6. Synthetic Control D0

D0 runs first. If H5 fails on D0 (dominant category emerges on flat options), abort the entire protocol — the null baseline is poisoned by prompt geometry, and no amount of positive results on D1/D2/D3 rescue that.

---

## 7. Analysis (Mirrors §1 Exactly)

Analysis code in `/tmp/null-model-runs/analyze.py`, written AFTER reruns complete, < 100 lines, zero free choices.

Exact decision rules:

- **H6 (run first):** for each domain, compute `schema_conformance_rate`. Fail H6 if any domain < 0.80. If H6 fails for domain X, H1 and H3 for X are auto-failed and skipped in analysis.

- **H1:** for each of D1, D2, D3 where H6 passed, compute `target_count = count(rerun where blind_classified_category == pre_registered_target)`. Pass H1 if `target_count ≥ 14` for at least 2 of 3 domains.

- **H2:** for each of D1, D2, D3, identify Haiku modal winner cell across the 20 Haiku reruns (after H6 conformance check). Run a full 9-cell grid for Sonnet (3 reruns) and Opus (3 reruns) on the same domain prompt. For each of Sonnet and Opus, identify the modal winner cell across its 3 grids. Pass H2 if Sonnet-modal-winner == Haiku-modal-winner AND Opus-modal-winner == Haiku-modal-winner, for at least 2 of 3 real domains. Any invalidated grid (per §3.1) auto-fails H2 for that domain.

- **H3:** for each of D1, D2, D3 where H6 passed, run `scipy.stats.binomtest(target_count, 20, 0.25, alternative='greater')`. Pass if p < 0.0125 for at least 2 of 3 domains.

- **H4:** run post-matrix falsification on modal winners of D1, D2, D3. Classify 3 verdicts. Pass if no single verdict accounts for all 3.

- **H5:** `scipy.stats.binomtest(d0_target_count, 20, 0.25, alternative='greater')` where `d0_target_count` is the most frequent category on D0. Pass if p ≥ 0.0125.

Any deviation is a protocol violation.

---

## 8. Protocol Amendments

Any change post-execution-start requires:
1. Dated "Amendment" section below.
2. Explicit justification.
3. Note affected hypotheses.
4. **Amendment counts as failure for any hypothesis where it relaxes a threshold or substitutes a test.** Blocks move-the-goalposts.

No amendments yet.

---

## 9. Expected Deliverable

`docs/null-model-validation-report.md`:
- H1-H6 pass/fail table with exact numbers.
- Schema conformance rate per domain (H6 output).
- Per-lesson decision: which of L1-L11 are supported, downgraded, or retracted.
- Co-error check results.
- Updated idea-matrix skill PR (if any).
- Codex round-5 invitation.

Budget for report + codex: ~$1.

---

## 10. Abort Conditions (v3 — Abort = Failure)

Protocol aborts on:
- Cumulative cost > 2× budget ($14).
- Banned-token scan trips >1 after 2 rebuild attempts per domain.
- Kappa < 0.75 between model judges per domain → that domain's H1/H3 = FAILED (not aborted; v2 rule).
- Pedro rejects conceptual-leakage review and cannot construct acceptable neutral prompt.
- **NEW v3:** Schema conformance rate for any domain < 0.50 after re-dispatches → domain auto-fails H6, H1, H3; if this happens on ≥2 domains, whole protocol aborts (prompt-only schema discipline is unfixable in this regime).

**Rule:** every abort counts as failure of the relevant hypothesis. Never "inconclusive". Never "dropped silently".

On abort, write `docs/null-model-validation-abort.md`: trigger, partial data, which hypotheses fail, which lessons retract/downgrade.

---

## 11. Changelog

### v4 → v5 (this version)

Addresses Codex round-5 review of v4:

| # | v4 flaw | v5 fix |
|---|---------|--------|
| 14 | H2 ran only Haiku modal-winner cell against Sonnet/Opus. Could not measure cross-model winner identity — Sonnet might rank an untested cell higher. False-positive structurally. | §1 H2 redesigned: full 9-cell grid for Sonnet (×3 reruns) and Opus (×3 reruns) per domain. Compare each model's modal winner against Haiku's. Cost +~$1.50; total budget $8-9. |
| 15 | H6 conformance formula `ok / (total − dropped)` excluded dropped cells from the denominator, so widespread failure could report high conformance among survivors. | §3.1 formula changed to fixed denominator: `ok_cells / total_dispatched_cells` (180 per domain). Drops, retries, and invalidated reruns all count against. |
| 16 | Main 9-cell rerun with exactly 1 dropped cell survived with no analyst-time semantics. Same partial-failure ambiguity v4 fixed for H2 single-cell. | §3.1 single rule: ANY drop invalidates the entire rerun (counts as 9 dropped cells toward H6). Removes post-hoc discretion about scoring 8-of-9 grids. Same rule applied to H2 grids. |

### v3 → v4 (commit 478e861)

Addresses Codex round-4 review of v3:

| # | v3 flaw | v4 fix |
|---|---------|--------|
| 11 | Lexical gate self-contradicted the env blocks it introduced: D1 env block contained "cache infrastructure"; D0 env block contained "rollback"; both were in the banned-token list. Gate would abort by construction. | §3 lexical gate now scans ONLY model-generated text (`mechanism_novelty`, `dealbreaker`), not the prompt. The prompt's env block can mention vocabulary that the model is forbidden from re-using. |
| 12 | Schema validator only checked dimension key-set + convention string. Did not verify score types or 1-10 bounds, did not recompute composite, did not check dealbreaker grounding. Corrupt outputs counted as `ok`. | §3.1 expanded from 2 gates to 7 gates: parse, schema, convention, **score-int-in-bounds**, **composite-recompute (model value discarded)**, **banned-token scan on output**, **dealbreaker infrastructure grounding (must appear in env block)**. |
| 13 | H2 ran single-cell reruns (Sonnet/Opus) but the drop rule required ≥2 failed cells to mark a rerun dropped. Single-cell reruns could fail twice and leave a missing composite with no analysis-time semantics — free choice at score time. | §3.1 explicit rule: single-cell reruns that fail twice count as **0 in the fixed 5-run denominator** (a miss). §7 H2 description references this rule explicitly. |

### v2 → v3 (commit 25b35e4)

Addressed autoimprove#105 findings from MATRIX_5:

| # | v2 flaw | v3 fix |
|---|---------|--------|
| 9 | Assumed prompt-only schema discipline worked. MATRIX_5 disproved: 4/9 cells invented extra dimensions (5-7 dims instead of 4). | §3 template includes explicit "Your output will be schema-validated and rejected" + enumeration of forbidden dimension names. §3.1 adds schema validation procedure. H6 enforces ≥80% conformance. |
| 10 | Neutral prompts lacked codebase infrastructure context, leading haiku to hallucinate dealbreakers (L8). | §2.2 introduces Environment Blocks; each domain pre-registers one in §2. §3 template has mandatory "Available Infrastructure" section. |

### v1 → v2 (commit c9ffd33)

Addressed Codex round-3 (see v2 document history). Summary:
- §1/§7 alignment (single test per H, no post-hoc choice).
- Power analysis for n=20 threshold 14/20.
- D0 integrated (first, with categories).
- MEE categories via single-axis principle.
- Lexical ban + human conceptual-leakage gate.
- Kappa ≥ 0.75, human 3rd judge.
- Single test per hypothesis.
- Abort = hypothesis failure.

### v3 meta-commentary

v3 is now constrained by 3 rounds of adversarial review (Codex rounds 2 + 3 + issue #105). A v4 would need external human coders (not Pedro alone, to eliminate the human-also-correlated-to-Claude-outputs problem) and n≥30 per domain for power ≥0.7 on modest effects — out of current budget. v3 is the defensible floor given available resources.
