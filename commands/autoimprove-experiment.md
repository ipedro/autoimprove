---
name: autoimprove-experiment
description: Interactive experiment CRUD — create, list, or remove experiments manually without running the grind loop.
argument-hint: "<create|list|remove> [options]"
---

Invoke the `autoimprove:experiment` skill now. Do not do any work before the skill loads.

Arguments: $ARGUMENTS

---

## Subcommands

| Subcommand | Description |
|-----------|-------------|
| `create` | Interactive onboarding: define a hypothesis, target files, constraints, and expected outcome. Writes `experiments/<id>/context.json` with `status: "pending"`. |
| `list` | Rich table view of experiments with optional filters. |
| `remove` | Interactive selection and confirmation before deleting experiment records. |

## Usage Examples

```
# Start the interactive experiment-creation wizard
/autoimprove experiment create

# List all experiments (last 20)
/autoimprove experiment list

# List only pending experiments
/autoimprove experiment list --status pending

# Filter by theme, show recent entries
/autoimprove experiment list --theme failing_tests --since 2026-03-01

# Remove one or more experiment records interactively
/autoimprove experiment remove
```

## Arguments for `list`

| Argument | Description |
|----------|-------------|
| `--status <status>` | Filter by status: `pending`, `running`, `completed`, `failed`, `crashed`. |
| `--theme <name>` | Substring match on the theme field. |
| `--since <date>` | ISO date (`YYYY-MM-DD`). Show only experiments created on or after this date. |
| `--last N` | Cap results to the N most recent entries (default: 20). |

## What `create` Produces

A new directory `experiments/<YYYYMMDD-HHMMSS>/` with a `context.json`:

```json
{
  "id": "20260403-143012",
  "theme": "failing_tests",
  "hypothesis": "The off-by-one error in range filter causes test failures",
  "target_files": ["src/filter.ts", "tests/filter.test.ts"],
  "constraints": { "max_files": 3, "max_lines": 150 },
  "expected_outcome": "All date-range filter tests pass",
  "status": "pending",
  "created_at": "2026-04-03T14:30:12Z"
}
```

Run `pending` experiments via `/autoimprove run --experiment <id>`.

## What `remove` Does

1. Lists removable experiments (never removes `running` experiments without confirmation).
2. Asks for explicit confirmation before any deletion.
3. Deletes `experiments/<id>/` directory.
4. Removes the matching row from `experiments/experiments.tsv` (if present).

## Related Commands

- `/autoimprove run` — execute the grind loop (or run a specific pending experiment with `--experiment <id>`)
- `/autoimprove history` — browse the experiment log with verdict/theme filters
- `/autoimprove report` — session summary with metric trends
