# Debate Output Schema

## Per-Round Structure

Each round in the `ROUNDS` array (and in `round-N.json` incremental files):

```json
{
  "round": 1,
  "run_id": "20260327-103045-retrieve-prefetch-design",
  "enthusiast": {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "file": "path/to/file.ext",
        "line": 42,
        "description": "Brief description of the issue",
        "evidence": "Specific code reference or reasoning",
        "prior_finding_id": null
      }
    ]
  },
  "adversary": {
    "verdicts": [
      {
        "finding_id": "F1",
        "verdict": "valid|debunked|partial",
        "severity_adjustment": "critical|high|medium|low|null",
        "reasoning": "Evidence-based reasoning"
      }
    ]
  },
  "judge": {
    "rulings": [
      {
        "finding_id": "F1",
        "final_severity": "critical|high|medium|low|dismissed",
        "winner": "enthusiast|adversary|split",
        "resolution": "Actionable one-liner: what to fix and how"
      }
    ],
    "summary": "N confirmed, M debunked. Net: X high, Y medium.",
    "convergence": false
  },
  "errors": ["enthusiast_malformed_json"],
  "converged": false
}
```

`errors` is omitted when empty. `converged` reflects the **deterministic orchestrator
check** (not the judge's self-reported value).

---

## Final Run Structure (`run.json`)

```json
{
  "run_id": "20260327-103045-retrieve-prefetch-design",
  "meta": {
    "target": ".xgh/specs/2026-03-27-retrieve-prefetch-design.md",
    "date": "2026-03-27T10:30:45Z",
    "rounds_planned": 4,
    "rounds_completed": 4,
    "converged_at_round": null,
    "model": "claude-sonnet-4-6",
    "judge_llm_convergence_mismatches": 1
  },
  "rounds": [ ],
  "confirmed": [
    {
      "id": "F2",
      "severity": "critical",
      "winner": "adversary",
      "round": 1,
      "description": "Stuck-running state never reset by session-start",
      "resolution": "Add TTL expiry logic in session-start and freshness script"
    }
  ],
  "debunked": [
    {
      "id": "F4",
      "round": 1,
      "reason": "Crash before Step 10 leaves state=running, not state=complete"
    }
  ],
  "final_summary": "14 confirmed, 3 debunked. Net: 1 critical, 3 high, 7 medium, 3 low.",
  "total_rounds": 4,
  "converged_at_round": null
}
```

---

## Run Metadata (`meta.json`)

Written at run start (`status: running`), updated at completion:

```json
{
  "run_id": "20260327-103045-retrieve-prefetch-design",
  "target": ".xgh/specs/2026-03-27-retrieve-prefetch-design.md",
  "date": "2026-03-27T10:30:45Z",
  "rounds_planned": 4,
  "rounds_completed": 4,
  "converged_at_round": null,
  "status": "complete",
  "model": "claude-sonnet-4-6",
  "total_findings": 35,
  "confirmed": 26,
  "debunked": 9,
  "by_severity": { "critical": 1, "high": 5, "medium": 11, "low": 9 },
  "judge_llm_convergence_mismatches": 1
}
```

---

## Run Folder Layout

```
~/.autoimprove/runs/<RUN_ID>/
  meta.json       # written at start; updated at end
  round-1.json    # written after round 1 completes (incremental)
  round-2.json    # written after round 2 completes
  ...
  run.json        # written at end (complete output)
```

All runs are stored privately in `~/.autoimprove/` — never in the project or plugin.

---

## Patterns Observed from Real Runs

These patterns emerged from actual usage and inform judge calibration:

**Convergence gap:** The judge's self-reported `convergence: true` can diverge from
the deterministic check when each round introduces new finding IDs. Track
`judge_llm_convergence_mismatches` to detect judges that converge too eagerly.
Real example: 4-round run on a 228-line design spec — judge called convergence at round 3
but deterministic check found new finding IDs in every round.

**Severity inflation:** Enthusiasts tend to escalate `critical` for systemic design issues
that are `high` once bounded (e.g., deadlocks that require a prior crash). Adversary
correctly downgrades ~30% of critical findings to high.

**Debunk rate:** Healthy debunk rate is 20–35%. Below 20% suggests the adversary is too
permissive. Above 40% suggests the enthusiast is generating noise.

**Finding discovery curve:** In a 4-round run on a 200+ line spec, new findings were
discovered in every round (no hard convergence). Round 1 produces the most findings;
subsequent rounds find progressively more obscure issues.

**Round discovery distribution (real run, 4 rounds, 35 total findings):**
- Round 1: 17 findings (49%)
- Round 2: 7 findings (20%)
- Round 3: 6 findings (17%)
- Round 4: 5 findings (14%)
