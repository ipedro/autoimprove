# Debate Output Schema

Each round produces this structure:

```json
{
  "round": 1,
  "enthusiast": {
    "findings": [
      {
        "id": "F1",
        "severity": "critical|high|medium|low",
        "file": "path/to/file.ext",
        "line": 42,
        "description": "Brief description",
        "evidence": "Specific code reference",
        "prior_finding_id": null
      }
    ]
  },
  "adversary": {
    "verdicts": [
      {
        "finding_id": "F1",
        "verdict": "valid|debunked|partial",
        "severity_adjustment": "high|null",
        "reasoning": "Evidence-based reasoning"
      }
    ]
  },
  "judge": {
    "rulings": [
      {
        "finding_id": "F1",
        "final_severity": "high|dismissed",
        "winner": "enthusiast|adversary|split",
        "resolution": "Actionable one-liner"
      }
    ],
    "summary": "N confirmed, M debunked.",
    "convergence": false
  }
}
```

The final output wraps all rounds:

```json
{
  "rounds": [ /* ...per-round objects... */ ],
  "final_summary": "Human-readable summary of confirmed findings",
  "total_rounds": 2,
  "converged_at_round": null
}
```
