# autoimprove

Autonomous codebase improvement loop for [Claude Code](https://docs.anthropic.com/en/docs/claude-code) and Codex. Inspired by [karpathy/autoresearch](https://github.com/karpathy/autoresearch).

You program the improvement strategy. The system modifies code, evaluates against your benchmarks, and keeps or discards changes via git worktree isolation. You wake up to a log of experiments and a better codebase.

## How it works

```
autoimprove.yaml          evaluate.sh              experimenter agent
(you write this)          (deterministic scoring)   (blind to scoring)
       │                         │                         │
       ▼                         ▼                         ▼
┌─────────────┐  spawn   ┌──────────────┐  evaluate  ┌──────────┐
│ orchestrator │────────▶ │  worktree    │──────────▶ │ verdict  │
│   (loop)    │◀─────────│  experiment  │            │ keep or  │
│             │  commit   │              │            │ discard  │
└─────────────┘          └──────────────┘            └──────────┘
```

The orchestrator picks improvement themes (failing tests, TODOs, coverage gaps), spawns an experimenter agent into an isolated git worktree, then evaluates the result with a deterministic script. The experimenter never sees your metrics or scores — it makes changes it genuinely believes are improvements.

**Scoring uses set logic, not weighted averages.** A change is kept only if no metric regresses and at least one improves. A single regression vetoes the entire experiment.

## Quick start

Claude Code:

```bash
# 0. Install the plugin (one-time)
claude plugin marketplace add https://github.com/ipedro/autoimprove
claude plugin install autoimprove

# 1. Inside your project, run:
/autoimprove init
```

Codex:

```text
$autoimprove:init
```

`/autoimprove init` in Claude Code and `$autoimprove:init` in Codex are interactive — they detect your project, run your tests, and scaffold everything:

```
autoimprove initialized for my-project (Node.js)

Gates
  [PASS] tests — npm test (42 tests, 0 failures)

Metrics (baseline)
  test_count: 42
  todo_count: 7

Files written:
  autoimprove.yaml        ← your improvement strategy
  benchmark/metrics.sh   ← measures test_count + todo_count

Next step: /autoimprove run --experiments 3
```

You don't write a benchmark script — init generates one from your project. Then:

Claude Code:

```bash
# 2. Run the improvement loop (3 trial experiments first)
/autoimprove run --experiments 3

# 3. See what happened
/autoimprove report
```

Codex:

```text
$autoimprove:autoimprove --experiments 3
$autoimprove:report
```

## The autoresearch mapping

| autoresearch | autoimprove |
|---|---|
| `train.py` (agent edits this) | Your source code |
| `prepare.py` (immutable eval) | `evaluate.sh` |
| `program.md` (human strategy) | `autoimprove.yaml` |
| `val_bpb` (fitness number) | Per-metric set logic |
| `git reset --hard` | `git worktree remove` |

The key insight from autoresearch: **the human doesn't edit the code — they edit the improvement strategy.** You tune `autoimprove.yaml`, not your source files.

## Safety

autoimprove is conservative by default:

- **Hard gates first** — tests and typecheck must pass or the change is immediately discarded
- **No metric can regress** — a single regression vetoes, regardless of other improvements
- **Epoch drift halt** — session stops if cumulative drift exceeds 5% from session start
- **Trust starts small** — tier 0 limits experiments to 3 files, 150 lines. Scope expands only after consecutive successful keeps
- **Fast-forward only** — rebase conflicts = discard. Clean linear history guaranteed
- **Experimenter is blind** — can't game metrics it can't see
- **Evaluation is deterministic** — `evaluate.sh` (bash + jq), no LLM in the scoring loop

## Configuration

`autoimprove.yaml` lives in your project root:

```yaml
gates:
  - name: tests
    command: npm test
  - name: typecheck
    command: npx tsc --noEmit

benchmarks:
  - name: project-metrics
    type: script
    command: bash benchmark/metrics.sh
    metrics:
      - name: test_count
        extract: "json:.test_count"
        direction: higher_is_better
        tolerance: 0.02       # max acceptable regression
        significance: 0.01    # min meaningful improvement

themes:
  auto:
    strategy: weighted_random
    priorities:
      failing_tests: 5
      todo_comments: 3
      coverage_gaps: 2
```

See [docs/configuration.md](docs/configuration.md) for the full schema.

## Prerequisites

- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) or Codex
- `jq` (`brew install jq` / `apt install jq`)
- bash 4+
- A project with a test suite

## Installation

autoimprove ships both a Claude Code plugin manifest and a Codex plugin manifest.

**Claude Code**

1. Add as a marketplace:

```bash
claude plugin marketplace add https://github.com/ipedro/autoimprove
```

2. Install the plugin:

```bash
claude plugin install autoimprove
```

The `/autoimprove` commands are now available in every Claude Code session.

**Codex**

Codex support is exposed through the repo-local `.codex-plugin/plugin.json` manifest and the shared `skills/` directory. Codex presents plugin skills with the `autoimprove:` namespace so they do not collide with generic names like `init` or `report`. The primary entrypoints are:

```text
$autoimprove:init
$autoimprove:autoimprove --experiments 3
$autoimprove:report
```

> **Local dev:** If you're working inside this repo, Claude Code can use `.claude-plugin/plugin.json` and Codex can use `.codex-plugin/plugin.json` directly from the checkout.

## Documentation

- [Getting Started](docs/getting-started.md) — install, configure, first run
- [Usage Guide](docs/usage.md) — setup walkthrough, running sessions, tuning strategy, benchmark patterns
- [Configuration](docs/configuration.md) — full `autoimprove.yaml` reference
- [How It Works](docs/how-it-works.md) — architecture, scoring, safety mechanisms
- [Commands](docs/commands.md) — `/autoimprove run`, `report`, `init`
- [Troubleshooting](docs/troubleshooting.md) — common issues and how to fix them

## Project structure

```
.claude-plugin/
  plugin.json              # Claude Code plugin manifest
  commands/                # Claude slash-command entrypoints
.codex-plugin/
  plugin.json              # Codex plugin manifest
skills/
  autoimprove/             # Codex skill alias for the main run loop
  init/                    # scaffold autoimprove.yaml
  report/                  # summarize outcomes
commands/
  autoimprove.md           # Claude /autoimprove alias
  autoimprove-init.md      # Claude /autoimprove init
  autoimprove-report.md    # Claude /autoimprove report
scripts/
  evaluate.sh              # the prepare.py — deterministic evaluation
```

## Design

The full design spec — including adversarial review, constraint philosophy, and the case for set logic over weighted composites — is in [DESIGN.md](DESIGN.md).

## License

MIT
