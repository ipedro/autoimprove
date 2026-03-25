# Configuration Reference

autoimprove is configured via `autoimprove.yaml` in your project root. Run `/autoimprove init` to generate a starter file.

## Top-Level Structure

```yaml
project:
  name: my-project
  description: "Optional description"

themes:
  - name: todo_comments
    description: "Resolve TODO/FIXME comments"
    focus_paths: ["src/"]
    forbidden_paths: ["src/generated/"]

gates:
  - name: tests
    command: "npm test"
  - name: typecheck
    command: "npm run typecheck"

benchmarks:
  - name: dogfood
    command: "npm run benchmark"
    metrics:
      - name: score
        extract: "json:.score"
        direction: higher_is_better
        tolerance: 0.02
        significance: 0.01

safety:
  epoch_drift_threshold: 0.05
  coverage_gate_threshold: 0.80
  stagnation_window: 5
  state_checkpoints:
    - "*.sqlite"
  clean_between_experiments:
    - "rm -rf .cache/benchmark-*"

session:
  max_experiments_per_session: 10
  budget_usd: 5.00

trust_ratchet:
  tier_0: { max_files: 3, max_lines: 150 }
  tier_1: { max_files: 6, max_lines: 300, after_keeps: 5 }
  tier_2: { max_files: 10, max_lines: 500, after_keeps: 15 }
  tier_3: { max_files: null, max_lines: null, propose_only: true }
```

## Sections

### themes

What the experimenter tries to improve. Each theme has:
- `name` — identifier used in logs and `--theme` flag
- `description` — plain-language instruction to the experimenter
- `focus_paths` — directories to look in (optional)
- `forbidden_paths` — files/dirs the experimenter must not touch
- `cooldown` — experiments to skip after a stagnation (default: 3)

### gates

Hard gates run before benchmarks. Any failure immediately discards the experiment.
- `name` — identifier for log output
- `command` — shell command; exit 0 = pass, non-zero = fail

Gates are fast-fail: the first failure skips remaining gates.

### benchmarks

Each benchmark runs a command and extracts one or more metrics.

**metric.extract formats:**
- `json:.field` — parse stdout as JSON, extract field
- `grep PATTERN` — run grep against stdout, extract first match
- `regex:PATTERN` — apply regex to stdout, capture group 1

**metric.direction:** `higher_is_better` or `lower_is_better`

**metric.tolerance:** fractional regression allowed before discard (e.g. `0.02` = 2%)

**metric.significance:** minimum improvement fraction to count as a keep (e.g. `0.01` = 1%)

### safety

- `epoch_drift_threshold` — halt the session if cumulative drift from the frozen epoch baseline exceeds this fraction
- `coverage_gate_threshold` — changed files must have this fraction of test coverage (0.0 to disable)
- `stagnation_window` — exit a theme early after this many consecutive non-improvements
- `state_checkpoints` — glob patterns of files to hash before/after each experiment for isolation checks
- `clean_between_experiments` — commands run between experiments to reset external state

### session

- `max_experiments_per_session` — hard cap on experiments per run
- `budget_usd` — approximate token cost cap (informational, not enforced in v1)

### trust_ratchet

Controls how much scope the experimenter gets as it earns trust. Tiers escalate after N consecutive keeps with zero regressions. Any regression drops one tier.

Tier 3 changes are never auto-merged — they become proposals for human review.
