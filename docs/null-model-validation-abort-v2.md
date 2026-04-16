# Null-Model Validation v10.3 — Protocol Abort (2026-04-16)

**Trigger:** §10 abort condition 5 — schema conformance rate < 0.50 on ≥2 domains after re-dispatches.

## Partial Results

### D0 (synthetic control, null test) — PASS

Fresh run at `/tmp/null-model-runs-v2/D0/` under Fix A + Fix B:

| Metric | Value | Threshold | Result |
|--------|-------|-----------|--------|
| H5 p-value | 0.3828 | ≥ 0.0125 | ✅ PASS (huge margin) |
| H6 rate | 180/180 (100%) | ≥ 0.80 | ✅ PASS |
| H7 rate | 20/20 (100%) | ≥ 0.80 | ✅ PASS |

Semantic category distribution: morning 3, afternoon 5, evening 6, other 6. No category dominant. Diagnostic position/label counts (B:7, A:4, C:3) show mild per-label imbalance, but Fix B decoupled label from semantic — no semantic category dominated.

**H5 confirms:** matrix does NOT fabricate structure on flat options.

### D1 (caching strategy) — H6 UNFIXABLE

| Metric | Value | Threshold | Result |
|--------|-------|-----------|--------|
| H6 rate | 51/180 (28.3%) | ≥ 0.80 | ❌ FAIL |
| H7 rate | 0/20 (0%) | ≥ 0.80 | ❌ FAIL |
| Target count | 0/20 | ≥ 14 for H1 | H1 FAIL |
| H3 p-value | 1.0 | < 0.0125 | H3 FAIL |

**Root cause:** banned tokens for D1 per §2 = `{redis, memcached, lru, cdn, cache, ttl, eviction, invalidation, hazelcast, ignite}`. The domain is "caching strategy" — its core vocabulary includes `cache`, `lru`, `ttl`, `eviction`, `invalidation` as CONCEPTS, not product names. Haiku cannot describe a caching mechanism (in `mechanism_novelty` or `dealbreaker`) without using at least one banned token. Retry-with-explicit-reason (per §3.1 Gate 6) does not resolve this — there is no synonym for "cache" that communicates the concept.

Example mechanism_novelty strings that failed:
- "In-process LRU eviction reduces database round-trips..." → failed `lru`
- "Coordinating TTL invalidation across replicas..." → failed `ttl`, `invalidation`
- "The cache layer at each replica..." → failed `cache`

### D2 (schema migration) — PASS ALL

| Metric | Value | Threshold | Result |
|--------|-------|-----------|--------|
| H6 rate | 179/180 (99.4%) | ≥ 0.80 | ✅ PASS |
| H7 rate | 19/20 (95%) | ≥ 0.80 | ✅ PASS |
| Target count | 14/20 | ≥ 14 for H1 | ✅ H1 PASS |
| H3 p-value | ~3×10⁻⁵ | < 0.0125 | ✅ H3 PASS |

Target category `parallel-build-then-swap` wins 14/20 reruns. Label position counts for all solo winners: A:8, B:5, C:5 — no position bias (under uniform p=1/3, P(X≥8 in 18) ≈ 0.22, not significant). Target wins are distributed across labels because Fix B rotated the semantic→label mapping per rerun.

**D2 confirms:** idea-matrix does produce a consistent semantic signal on a real domain when the banned-token list is well-formed (product names only, not domain concepts).

### D3 (retry strategy) — H6 UNFIXABLE

| Metric | Value | Threshold | Result |
|--------|-------|-----------|--------|
| H6 rate | 43/180 (23.9%) | ≥ 0.80 | ❌ FAIL |
| H7 rate | 0/20 (0%) | ≥ 0.80 | ❌ FAIL |
| Target count | 0/20 | ≥ 14 for H1 | H1 FAIL |
| H3 p-value | 1.0 | < 0.0125 | H3 FAIL |

**Root cause:** same as D1. Banned tokens for D3 per §2 = `{tenacity, retry, backoff, circuit, hystrix, resilience4j, polly, jitter}`. `retry`, `backoff`, `circuit`, `jitter` are CONCEPTS in the failure-handling domain. The problem statement itself ("retry strategy for flaky external API") forces the concept. Haiku cannot describe a failure-handling mechanism without using at least one.

## Hypothesis Verdicts (per §7)

| Hypothesis | Verdict | Reasoning |
|------------|---------|-----------|
| H1 (L5a winner stability) | **FAIL** | Only D2 passes (1/3 domains). Threshold is ≥2/3. |
| H2 (cross-model agreement) | **NOT EVALUATED** | Auto-fail for D1/D3 by §1 H2 prerequisite (requires H6∧H7). D2 alone insufficient per §7 H2 final ≥2/3 rule. |
| H3 (non-uniformity) | **FAIL** | Only D2 passes (p=3e-5). Threshold is ≥2/3. |
| H4 (post-matrix falsification) | **NOT EVALUATED** | Requires modal winners across all 3 domains; D1/D3 have no modal winner. |
| H5 (null — no fabrication) | **PASS** | D0 p=0.3828 ≥ 0.0125. |
| H6 (cell-level conformance) | **FAIL** | D0=1.0, D1=0.283, D2=0.994, D3=0.239. Not ≥0.80 for all 4. |
| H7 (rerun-level validity) | **FAIL** | D0=1.0, D1=0.0, D2=0.95, D3=0.0. Not ≥0.80 for all 4. |

## Which L1–L11 Are Supported, Downgraded, Retracted

- **L5a (3×3 matrix winner-identity is stable across neutral reruns):** Cannot be supported; single-domain evidence (D2) is below the pre-registered 2/3 bar. **Downgrade to unvalidated.**
- **L7 (prompt-only schema enforcement drifts):** Supported by D0 rerun (0 drifts) and D2 (1 drift across 180 cells). **Upgrade to validated** under proper banned-token lists. **However:** for domains where banned tokens overlap with domain concepts, prompt-only discipline cannot enforce schema against natural reasoning — this is a *different* failure mode than what L7 originally described. New finding.
- **L8 (infrastructure dealbreaker grounding):** Indirectly validated — D0 and D2 had zero dealbreaker grounding failures after Fix B runs. Not the primary evaluation target of this protocol.
- **L11 (post-matrix falsification):** Not evaluated (requires modal winners). **Downgrade to unvalidated.**
- Other lessons (L1, L2, L3, L4, L5b, L6, L9, L10): not directly tested by this protocol; unchanged.

## Root-Cause Finding — Protocol Design Flaw

The banned-token gate in §3.1 Gate 6 was designed to prevent the model from parroting implementation hints from the prompt context. The implementation assumed banned tokens are substitutable by synonyms or more general vocabulary — a safe assumption when banned tokens are product/library names (D2 case: `flyway`, `alembic`, `gh-ost`) because the underlying concept ("schema migration") has plenty of neutral vocabulary.

This assumption breaks when banned tokens are **domain-intrinsic concepts**, as in D1 (`cache`, `ttl`, `lru`, `eviction`) and D3 (`retry`, `backoff`, `circuit`, `jitter`). The core concept BEING ASKED ABOUT is on the banned list. No synonyms exist — describing the mechanism requires the word.

This flaw survived Codex adversarial rounds 1–14 because the debate focused on statistical discipline (tie rules, sample floors, invalidation semantics) and not on the semantic content of the banned lists themselves. The banned-token lists were treated as a fixed input, not a design choice.

**Conclusion:** H6/H7 as currently operationalized measure BOTH schema discipline AND prompt-banned-token compatibility. For the latter they silently under-measure on domain-intrinsic-vocabulary domains. A future protocol should either:
1. Separate H6 (schema discipline) from a new H6b (banned-token compatibility), OR
2. Require banned-token lists to be *product/library names only*, with concept vocabulary excluded from the ban list.

## What Was Validated Despite the Abort

- **Fix A (solo-only ranking, from commit 6c5ae99):** validated on D0 (null, H5 pass) AND D2 (positive signal, H1/H3 pass). The synergy_potential tautology that caused the original v10.1 abort is resolved.
- **Fix B (per-rerun balanced permutation, Amendment 2/3):** validated on D0 (semantic distribution matches null; diagnostic position bias does not leak into semantic bias) AND D2 (target wins distributed across labels: A:8, B:5, C:5 — no fabricated Label-B bias despite target = option B in all three real domains).
- **D2 semantic signal:** 14/20 target wins with p=3×10⁻⁵. For a single domain, this is strong internal validation that the matrix produces a meaningful winner on a well-posed domain.

## What Is NOT Validated

- L5a (winner stability across domains) — needed ≥2/3, got 1/3.
- H2 / L5b (cross-model agreement) — not evaluated, would require H6/H7 passing on ≥2 of 3 real domains.
- H4 / L11 (post-matrix falsification) — not evaluated, would require modal winners on all 3 real domains.

## Costs & Budget

- FASE 1 D0 re-run (v10.2): ~$0.50 (180 Haiku + retries)
- FASE 2 Haiku (D1+D2+D3): ~$2.00 (~790 dispatches)
- H2 Sonnet+Opus: NOT DISPATCHED (would have been ~$5)
- Blind coding: NOT DISPATCHED (would have been ~$0.30)
- **Total spent: ~$2.50 of $9 budget.** Remaining $6.50 preserved by honoring the §10 abort.

## Recommendation

**Do NOT amend and re-run with relaxed banned tokens.** Per §8 rule 4, "amendment counts as failure for any hypothesis where it relaxes a threshold or substitutes a test." Re-running after relaxing banned-token lists would either (a) be a test substitution under §8, voiding the hypothesis anyway, or (b) require full re-pre-registration with 3 new domains having tool-name-only banned lists.

The honest read: **the protocol design itself needs v11 before re-execution can produce clean L5a evidence**. The current abort is the correct scientific outcome — the protocol failed on its own terms, and the cause is a pre-registered design flaw.

Future work for a v11 protocol:
1. Replace D1 (caching) with a domain whose banned list contains only product names (e.g., "session storage" with banned = {redis, memcached, cookie-jar-name, session-store-name}).
2. Replace D3 (retry) with a similar shape (e.g., "rate limiting" with banned = {istio, envoy, nginx-module-names}).
3. Or: split H6 into schema discipline + banned-token compatibility, each with its own threshold, so domain-intrinsic-vocabulary concerns surface separately.

## Next Steps for This Cycle

- Preserve all v2 artifacts (`/tmp/null-model-runs-v2/`).
- Commit Amendments 2 and 3 + abort doc + toolkit v2 to repo.
- Do NOT dispatch H2 Sonnet/Opus or blind coding — they would require re-spending the preserved budget for no incremental information, since H1/H3 are already failed by abort.
- Update idea-matrix skill status: Fix A kept (validated); Fix B NOT propagated to skill yet (primacy bias is a Haiku-specific fix whose production impact needs its own design review).
