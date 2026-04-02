# /track - User Goal Management

Set measurable targets for the autoimprove loop. Goals are stored in `experiments/state.json` and injected into future `/autoimprove run` sessions so the system keeps working toward outcomes you care about.

## Commands

| Command | Description |
|---------|-------------|
| `/track` | Add a new goal through the interview flow |
| `/track list` | Show tracked goals and their status |
| `/track remove <name>` | Mark a goal as removed |

## Adding a goal

Run `/track`.

If benchmark commands are configured in `autoimprove.yaml`, the skill runs them first and shows the currently available metric keys. You pick one of those keys, set a target delta such as `-20%`, `+10%`, `>=90%`, or `<=5`, then choose a priority from `1` through `5`.

If there are no benchmark commands yet, `/track` falls back to a cold-start path: you describe the goal in plain language, the skill extracts a candidate metric name, confirms it with you, and saves the goal with `needs_validation: true`. The next `/autoimprove run` re-validates that metric against benchmark output.

Limits:

- maximum `3` active goals at a time
- priority `1` to `5` maps directly to a `1x` to `5x` goal weight

## How goals affect the loop

The run loop applies the B+C priority model:

- Floor slots: by default, `2` experiment slots per session can be reserved for active goals.
- Weighted pool boost: goals also enter the remaining slot pool with a `3x` base boost, multiplied by their `priority_weight`.
- Re-validation: goals marked `needs_validation: true` are checked again at run startup and marked `stale` if the metric key no longer exists.

Configure the floor-slot count in `autoimprove.yaml`:

```yaml
goals:
  floor_slots: 2
```

## Goal lifecycle

- `active` goals can be scheduled into future sessions
- `achieved` goals crossed their target after a kept experiment
- `stale` goals no longer match current benchmark output
- `removed` goals no longer affect the loop

## Listing and removing

`/track list` prints active goals first, then achieved goals, and summarizes removed or paused entries. Goals created through the cold-start path are marked so you can see they still need benchmark validation.

`/track remove <name>` matches goal names case-insensitively. Partial matches work only when they are unique; otherwise the skill asks for a more specific name before making changes.
