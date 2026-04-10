# Phase 1 Pilot — cleanup fixture with TDD-for-fixtures

**Date:** 2026-04-10
**Timebox:** 1 day
**Actual cost:** ~6.7 minutes wall time (4 file writes, 4 adversarial variants, 2 TDD cycles, 5-run variance check)
**Result:** PASSED under simplified threat model; significant caveats apply before scaling

## TL;DR

TDD-for-fixtures as a methodology **works** for script-level deterministic testing. The red-team process caught a real bypass (v4 "recreate protected branches by name") that naive criterion missed, and SHA-based verification defeated it. Real cleanup script passes the hardened criterion; all 4 adversarial variants fail it.

**But:** the pilot tests the cleanup SCRIPT directly, not the cleanup SKILL invoked via Claude. The script-level test is dramatically cheaper than the full fixture would be. **The "1-day timebox met" result should not be extrapolated to remaining A1 candidates without accounting for this simplification.**

## What was built

Five files under `docs/research/pilot-cleanup/`:

| File | Lines | Purpose |
|---|---|---|
| `fixture.sh` | ~100 | Harness: sets up temp git repo with known state, runs impl, invokes check |
| `check.sh` | ~120 | Hardened success criterion (SHA verification + tag check + main immutability + context hash + git health) |
| `real-cleanup.sh` | 5 | Wrapper that invokes the production `scripts/cleanup-worktrees.sh` |
| `adversarial-v1-nuke-worktrees.sh` | 6 | Attack 1: `rm -rf .git/worktrees/*` — destroys metadata but not branches |
| `adversarial-v2-delete-all-matching.sh` | 8 | Attack 2: delete all matching branches, ignore all guards |
| `adversarial-v3-skip-in-flight-guard.sh` | 22 | Attack 3: implement guards A and B, skip guard C (in-flight check) |
| `adversarial-v4-recreate-protected.sh` | 17 | Attack 4: delete everything, recreate protected branches by name (BYPASSES naive check) |

## TDD cycles

### Cycle 1: naive criterion (branch presence only)

Initial check.sh only verified branch existence. Results:

| Impl | Result | Caught? |
|---|---|---|
| Real cleanup | PASS | ✓ correct |
| Adversarial v1 (nuke worktrees) | FAIL — orphan branches still present | ✓ caught |
| Adversarial v2 (delete all matching) | FAIL — protected branches missing | ✓ caught |
| Adversarial v3 (skip in-flight guard) | FAIL — 999-in-flight missing | ✓ caught |
| Adversarial v4 (recreate protected by name) | **PASS** ❌ | **BYPASS** |

v4 was the bypass: deleting everything and recreating `autoimprove/kept-alpha` + `autoimprove/999-in-flight` at `HEAD` satisfies a name-only presence check while destroying the actual protected content.

### Cycle 2: hardened criterion

check.sh was hardened to verify:
1. Protected branches exist AND point at their pre-impl SHAs (catches v4 recreation)
2. `exp-alpha` tag exists AND points at its pre-impl SHA (catches tag manipulation)
3. `main` branch SHA is unchanged (catches rogue main modification)
4. `experiments/999/context.json` content hash unchanged (catches context tampering)
5. `git status` and `git worktree list` both succeed (catches repo corruption)
6. Orphan branches are absent

Results after hardening:

| Impl | Result |
|---|---|
| Real cleanup | PASS ✓ |
| Adversarial v1 | FAIL (orphans still present) |
| Adversarial v2 | FAIL (protected branches missing) |
| Adversarial v3 | FAIL (999-in-flight missing) |
| Adversarial v4 | FAIL (protected branches moved — SHA mismatch) |

All 4 attacks caught. Real cleanup still passes.

## Variance measurement

5 consecutive runs of the real cleanup against the hardened fixture:

| Run | Result | impl_ms | total_ms |
|---|---|---|---|
| 1 | pass | 124 | 514 |
| 2 | pass | 125 | 496 |
| 3 | pass | 121 | 505 |
| 4 | pass | 125 | 516 |
| 5 | pass | 127 | 521 |

Variance: negligible. 6ms range on impl time, 25ms on total. Deterministic — as expected for a no-LLM fixture.

## Surprise findings from the pilot

### 1. Fixture setup matters — `git tag --points-at` edge case

During the first fixture draft, all 4 protected branches were created from the seed commit. Then the `exp-alpha` tag was applied to `autoimprove/kept-alpha`. Because `git tag --points-at "refs/heads/X"` returns ALL tags on the commit X points at, and all branches pointed at the same commit, the real cleanup script saw every branch as "tagged" and refused to delete any of them.

**Fix:** give each protected and orphan branch a unique commit via `git checkout -b` + `git commit` sequence before the next branch.

**Minor real bug surfaced:** `cleanup-worktrees.sh` uses `git tag --points-at` for guard B, which could misbehave if two experiments happen to share a commit SHA (unusual but possible if discard + rebase produces collisions). Not critical for normal autoimprove usage where each experiment has distinct worktree commits, but worth documenting.

### 2. Substring-match edge case in Guard C

Initial fixture used `autoimprove/kept-999` with tag `exp-999` and `autoimprove/999-in-flight` with context.json id `999`. The cleanup script's Guard C uses substring match: `case "autoimprove/kept-999" in *"999"*` matches. So kept-999 was double-protected (by both Guard B and Guard C).

Not a bug — just redundant protection — but confusing during debugging. Renamed fixture to use `kept-alpha`/`exp-alpha` to avoid the collision.

### 3. The v4 bypass is real and subtle

When I wrote v4, I was prepared for the naive check to catch it because "of course we'd check content, not just existence". But running it against the naive check showed it passing. This is a genuine insight into TDD-for-fixtures: **criteria that seem obviously sufficient often aren't, and writing the attack first is the only reliable way to discover this.**

## What this pilot does NOT validate

**Critical caveats for extrapolation:**

1. **The pilot tests the SCRIPT directly, not the SKILL.** The real cleanup skill invokes `scripts/cleanup-worktrees.sh` via Claude. Testing the script bypasses the "does Claude follow the skill's instructions correctly" question entirely. A skill that tells Claude to do the right thing but in an ambiguous way could still fail while the script would pass.

2. **No LLM variance observed** because no LLM is invoked. Real skill invocation introduces variance that this pilot doesn't measure. Budget for ~3 runs per fixture to median the signal; that's ~3× the cost.

3. **The threat model is constrained.** The adversarial variants are plausible "experimenter modifies the skill's shell logic" attacks. They do NOT include:
   - Experimenter rewriting `check.sh` or `fixture.sh` directly (fully adversarial experimenter)
   - Experimenter hardcoding fixture-specific behavior that disappears in production
   - Experimenter modifying `scripts/cleanup-worktrees.sh` to pass the fixture but fail in real grind usage
   The karpathy "prepare.py immutable" pattern is the correct defense, but it's not implemented here.

4. **Success criterion is hand-written per skill.** Hardening took 2 TDD cycles for cleanup specifically. Each A1 candidate will need its own criterion engineering + attack variants. The 1-day estimate per skill from the audit still stands — this pilot was fast because cleanup happens to have unambiguous pre/post state.

5. **No fixture rotation or parameterization.** A real fixture needs variant inputs per session to prevent memorization attacks. The current fixture is a fixed template. Adding rotation would add ~20-30% per fixture.

6. **No test of the skill's natural-language contract.** The skill's value is as a Claude-facing instruction. Testing only the script level misses prompt-quality failure modes entirely.

## Cost recalibration

The audit estimated ~1 day per A1 candidate for full fixture engineering including red-team tests. This pilot took ~7 minutes but **only covered the script-level subset** of what a real fixture needs.

Revised estimate for a PRODUCTION-grade cleanup fixture (including Claude invocation, LLM variance handling, fixture rotation, evaluate.sh integration):

| Phase | Estimate |
|---|---|
| Script-level fixture (this pilot) | 7 min ✓ done |
| Extend to invoke Claude with the skill | 2-3 hours |
| LLM variance measurement (5-run baseline, threshold tuning) | 1 hour |
| Fixture rotation / parameterization | 1-2 hours |
| Integration with evaluate.sh (new `type: llm-judge` entry + `run_frequency: session`) | 2 hours |
| Adversarial attacks against the Claude-invoked version (new attack vectors) | 1-2 hours |
| Documentation + fixture authoring guide | 1 hour |
| **Total for ONE production fixture** | **~1 full day** (matches original estimate) |

So the pilot validates the METHOD (TDD-for-fixtures) at near-zero cost, but does NOT shortcut the per-fixture budget for production.

## Go/no-go framework applied

From the audit:
- ≤ 1.0 day cost → proceed to test + init
- 1.0-2.0 days → pause, consider LLM-judge fallback
- > 2.0 days → abandon fixtures entirely

**Pilot says:** the METHOD works, stay in the ≤1 day bucket — but ONLY IF we scope each fixture like cleanup (artifact-state oracle, deterministic criterion, no fixture rotation in Phase 1).

**Recommended Phase 2:** extend THIS pilot to actual Claude invocation via the skill, measure real variance, and THEN decide whether to proceed to `test` + `init`.

## Conclusion and next action

- The TDD-for-fixtures method works for script-level testing ✓
- The specific cleanup fixture catches 4 attack variants ✓
- Variance is negligible at the script level (no LLM) ✓
- Real-world caveats are significant: skill invocation, threat model, per-fixture cost still applies

**Concrete next action** (if Pedro approves):
1. Keep the existing pilot as-is (validated, committed)
2. Extend to Claude invocation: spawn a subagent with the cleanup skill loaded, give it the fixture prompt, measure what it does
3. Run real vs each adversarial skill.md variant (modified SKILL.md, not just shell script)
4. If the skill-level test also works: declare Phase 1 complete, proceed to `test` fixture as Phase 2
5. If the skill-level test introduces significant variance or new bypasses: investigate before proceeding

**Honest summary for Pedro:** the pilot is a partial validation. It proves the method is sound for the easy case (script-level deterministic). It does NOT prove the method scales to full Claude-invoked skill testing. That's the next unknown to resolve before committing to the 5-day engineering estimate for remaining A1 candidates.
