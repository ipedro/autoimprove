# Usage Guide

Practical guide for using autoimprove on a real project. Covers setup, running sessions, reading results, and tuning your strategy.

## Setting up a project

### 1. Install prerequisites

```bash
# macOS
brew install jq bash

# Linux
apt install jq
```

Verify bash version: `bash --version` (need 4+).

### 2. Initialize

Run `/autoimprove init` in your project root. The init skill will:
- Detect your project type (Node.js, Python, Rust, Go)
- Find your test command
- Suggest benchmarks
- Write `autoimprove.yaml`

### 3. Configure gates

Gates are binary pass/fail checks. Every experiment must pass all gates or it's immediately discarded.

```yaml
gates:
  - name: tests
    command: npm test
  - name: typecheck
    command: npx tsc --noEmit
  - name: lint
    command: npx eslint src/ --max-warnings 0
```

**Tip:** Start with just your test suite. Add typecheck and lint after you've seen the loop work.

### 4. Configure benchmarks

Benchmarks are the metrics you want to improve. Each metric needs:
- A command that produces output
- An extraction pattern to pull a number from that output
- A direction (higher or lower is better)
- Tolerance (how much regression is acceptable)
- Significance (how much improvement counts)

```yaml
benchmarks:
  - name: project-health
    type: script
    command: bash benchmark/metrics.sh
    metrics:
      - name: test_count
        extract: "json:.test_count"
        direction: higher_is_better
        tolerance: 0.0         # zero tolerance — test count must never drop
        significance: 0.05     # 5% improvement to count as meaningful
      - name: todo_count
        extract: "json:.todo_count"
        direction: lower_is_better
        tolerance: 0.0
        significance: 0.10     # 10% reduction to count
```

**Writing a benchmark script:**

The simplest benchmark is a shell script that outputs JSON:

```bash
#!/usr/bin/env bash
set -euo pipefail
DIR="$(cd "$(dirname "$0")/.." && pwd)"

test_count=$(grep -r "it(\|test(" "$DIR/test" --include="*.js" | wc -l | tr -d ' ')
todo_count=$(grep -rn "TODO\|FIXME" "$DIR/src" --include="*.js" | wc -l | tr -d ' ')

cat <<EOF
{"test_count": $test_count, "todo_count": $todo_count}
EOF
```

**Extraction patterns:**

- `json:.field_name` — parse JSON output with jq
- `json:.nested.field` — nested jq path
- `grep -oP '\d+(?= passed)'` — shell command piped through benchmark output

### 5. Configure themes

Themes tell the experimenter what kind of improvements to attempt:

```yaml
themes:
  auto:
    strategy: weighted_random
    priorities:
      failing_tests: 5     # highest priority
      todo_comments: 3
      coverage_gaps: 2
      lint_warnings: 2
    cooldown_per_theme: 3   # skip for 3 experiments after attempt
```

Higher priority numbers = more likely to be selected. Cooldown prevents hammering the same theme repeatedly.

### 6. Configure safety

```yaml
safety:
  epoch_drift_threshold: 0.05    # halt if metrics drift >5% from session start
  regression_tolerance: 0.02     # global default: 2% regression acceptable
  significance_threshold: 0.01   # global default: 1% improvement meaningful
  stagnation_window: 5           # stop theme after 5 non-improvements
```

Per-metric tolerance and significance (in benchmarks) override these globals.

### 7. Protect your evaluation infrastructure

```yaml
constraints:
  forbidden_paths:
    - autoimprove.yaml
    - benchmark/**
    - test/fixtures/**
  test_modification: additive_only
```

The experimenter can never touch these files. It can add tests but never delete or weaken assertions.

## Running a session

### First run — start small

```
/autoimprove run --experiments 3
```

Run just 3 experiments to verify everything works. Check the output:
- Did gates run correctly?
- Were metrics extracted?
- Did the experimenter make reasonable changes?

### Normal session

```
/autoimprove run
```

Runs up to `max_experiments_per_session` (default 20). Each experiment:
1. Picks a theme
2. Spawns experimenter in isolated worktree
3. Experimenter makes changes, commits
4. `evaluate.sh` runs gates + benchmarks
5. Keep or discard based on set logic

### Focused session

```
/autoimprove run --theme failing_tests
```

Only runs experiments for one specific theme. Useful when you know where improvements are needed.

### Overnight session

Set a higher experiment count and let it run:

```
/autoimprove run --experiments 50
```

Check results in the morning with `/autoimprove report`.

## Reading results

### Session summary

After each session, the orchestrator prints a summary:

```
autoimprove session complete

Experiments: 20 run, 4 kept, 11 neutral, 3 regressed, 2 failed
Epoch drift: +3.2%
Trust tier: 1 (consecutive keeps: 7)
Stagnated themes: lint_warnings
Budget: 20/20 experiments used

Kept experiments:
  #003 failing_tests: "Fix divide-by-zero bug in math.divide()"
  #007 todo_comments: "Implement string.truncate() from TODO"
  #011 coverage_gaps: "Add tests for wordCount edge cases"
  #016 todo_comments: "Add input validation to math functions"
```

### Morning report

```
/autoimprove report
```

Shows the same information plus drift analysis and stagnation details.

### Experiment log

`experiments/experiments.tsv` — the full log of every experiment:

```
id  timestamp            theme          verdict  improved    regressed  tokens  wall_time  commit_msg
001 2026-03-25T22:01:00  failing_tests  keep     test_count  -         45000   4m30s      Fix divide-by-zero bug
002 2026-03-25T22:08:00  lint_warnings  neutral  -           -         38000   3m15s      Clean up unused imports
003 2026-03-25T22:14:00  todo_comments  regress  -           todo_count 12000   1m02s      Implement truncate (broke tests)
```

### Per-experiment detail

`experiments/<id>/context.json` — full metric breakdown, model version, constraints, and the prompt hash for reproducibility.

## Tuning your strategy

### If too many experiments are discarded

- **Mostly `gate_fail`**: your test suite is failing on changes. Consider whether the experimenter's scope is too broad (lower `max_files`/`max_lines`) or whether the test suite is too fragile.
- **Mostly `regress`**: metrics are regressing. Check if tolerances are too tight. Some noise is normal — set tolerance to 2-5% for noisy metrics.
- **Mostly `neutral`**: changes aren't moving the needle. Lower `significance` thresholds, or add more metrics that capture meaningful improvement.

### If the loop stagnates quickly

- Add more themes or increase priority weights for productive themes
- Lower `cooldown_per_theme` to cycle through themes faster
- Check if the remaining improvements are too large for the current trust tier — the system needs consecutive keeps to escalate scope

### If you want more aggressive improvement

- Increase `max_experiments_per_session`
- Widen trust ratchet tiers (increase `max_files` and `max_lines`)
- Lower `significance_threshold` to accept smaller improvements
- Add more themes targeting different improvement types

### If you want more conservative behavior

- Lower `epoch_drift_threshold` (e.g., 2% instead of 5%)
- Set `tolerance: 0.0` on critical metrics (zero regression allowed)
- Reduce trust ratchet scope limits
- Increase `stagnation_window` so themes get more chances before stopping

## What makes a good benchmark

Good benchmarks are:
- **Deterministic** — same code produces the same number every time
- **Fast** — under 30 seconds ideally. The loop runs benchmarks on every experiment
- **Meaningful** — measures something you actually care about improving
- **Sensitive** — changes enough to detect real improvements (not always 100%)

Bad benchmarks:
- Timing-based metrics with high variance (use percentiles, not averages)
- Metrics that max out quickly (100% coverage = nothing left to improve)
- Metrics that depend on external state (network, databases)

## Common benchmark patterns

### Test count
```bash
grep -r "it(\|test(\|describe(" test/ --include="*.js" | wc -l | tr -d ' '
```

### TODO/FIXME count
```bash
grep -rn "TODO\|FIXME\|HACK\|XXX" src/ --include="*.js" | wc -l | tr -d ' '
```

### Source lines of code
```bash
find src/ -name "*.js" -exec cat {} + | grep -c -v '^[[:space:]]*$'
```

### Test-to-code ratio
```bash
test_lines=$(find test/ -name "*.js" -exec cat {} + | grep -c -v '^$')
src_lines=$(find src/ -name "*.js" -exec cat {} + | grep -c -v '^$')
echo "scale=2; $test_lines / $src_lines" | bc
```

### ESLint warning count
```bash
npx eslint src/ --format json 2>/dev/null | jq '[.[].messages | length] | add'
```

### Python — pytest + coverage
```bash
pytest --tb=no -q 2>&1 | tail -1 | grep -oP '\d+(?= passed)'
```

### Rust — clippy warning count
```bash
cargo clippy --message-format=json 2>&1 | grep '"level":"warning"' | wc -l | tr -d ' '
```
