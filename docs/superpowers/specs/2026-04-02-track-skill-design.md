# track skill — Design Spec
_2026-04-02_

## Problem

autoimprove's experiment loop selects themes autonomously, but users have specific outcomes they want to optimize for (e.g., "reduce test runtime by 20%"). There's no way to express these goals or give them priority in the loop.

## Design Decisions (resolved via idea-matrix)

| Decision | Winner | Confidence |
|----------|--------|------------|
| Priority model | B+C: 3× weight multiplier + guaranteed floor slots | Moderate (0.50) |
| Interview style | Benchmark-Led Guided Interview | Moderate (0.50) |
| Storage (v1) | `state.json` goals[] | — |
| Storage (v2) | `goals.yaml` (separate lifecycle file) | — |

## Architecture

`track` is a conversational skill that conducts the Benchmark-Led Guided Interview and persists goals in `state.json` under a `goals[]` key. The `run` skill reads this key on startup and injects active goals into the theme selection loop using the B+C priority model.

No new files in v1. `goals.yaml` promoted in v2 once lifecycle patterns are clear from real usage.

### state.json schema (goals section)

```json
{
  "goals": [
    {
      "name": "reduce test runtime",
      "target_metric": "test_runtime_ms",
      "target_delta": "-20%",
      "priority_weight": 3,
      "status": "active",
      "added_at": "2026-04-02"
    }
  ]
}
```

`status` values: `active` | `paused` | `achieved` | `removed`

## Commands

| Command | Action |
|---------|--------|
| `/track` | Start interview to add a new goal |
| `/track list` | List active goals with progress |
| `/track remove <name>` | Mark goal as `removed` |

## Interview Flow (Benchmark-Led)

```
1. Detect: does autoimprove.yaml have a benchmark script?
   Yes → execute it, parse JSON output, display metric table with current values
   No  → "What do you want to improve? Describe it."
         (prose → skill extracts candidate metric + confirms)

2. User selects target_metric from real benchmark output keys
   (not free text — prevents unfalsifiable goals)

3. "What's your target? (e.g. -20%, or absolute: under 2000ms)"

4. Pre-flight validation (two checks):
   a. key exists in benchmark output JSON?
   b. delta achievable within current tier constraints?
   Fail → explain constraint, offer adjustment

5. "How urgent? (1-5)" → maps to priority_weight (1=1×, 5=5×)

6. Confirm summary → write to state.json goals[]
```

### Cold-start fallback (no benchmarks)

User describes goal in prose → skill extracts metric name + delta → stores with a `needs_validation: true` flag → `run` validates on first experiment.

## Integration with `run`

On startup, `run` reads `state.json goals[]` and:

1. **Injects active goals** into the theme pool with 3× weight multiplier
2. **Reserves N floor slots** (default: 2) per session for goals, regardless of competition
3. **Re-validates** each goal's `target_metric` against current benchmark output — if metric disappeared, warns and skips that goal
4. **After each experiment**: checks if `target_metric` moved toward `target_delta` in benchmark results — if threshold crossed, marks `status: "achieved"`

## Constraints

- `priority_weight` range: 1–5 (maps to 1×–5× multiplier in theme selection)
- Floor slots: configurable in `autoimprove.yaml` under `goals.floor_slots` (default: 2)
- Max concurrent active goals: 3 (prevents floor from consuming entire session)
- `run` double-validates goals on startup (independent of track's pre-flight) — catches benchmark schema drift between track and run

## Out of Scope (v1)

- Goal progress history over time (v2 with `goals.yaml`)
- Goal expiry / deadline enforcement
- Automatic goal suggestion from experiment history
- `/track pause` and `/track resume` commands
