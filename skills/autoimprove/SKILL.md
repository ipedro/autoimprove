---
name: autoimprove
description: |
  Main entry point for the autonomous improvement loop. Use when the harness calls `Skill(autoimprove)`, when the user runs `/autoimprove`, or when the user asks to start the full research → experiment → judge → converge flow.

  This is an alias for the `run` skill. It exists so callers can invoke the top-level `autoimprove` skill name directly without failing with "Unknown skill: autoimprove".
argument-hint: "[--experiments N] [--theme THEME] [--resume] [--phase propose]"
allowed-tools: [Read, Write, Edit, Bash, Glob, Grep, Agent]
---

Treat this invocation as equivalent to the `run` skill.

Before doing any work, read `skills/run/SKILL.md`, then follow its instructions exactly while preserving any user-supplied arguments from this `autoimprove` invocation.

Key requirements:

1. Do not do any work before loading `skills/run/SKILL.md`.
2. Preserve the same argument semantics as `run`.
3. Execute the full orchestrator flow from the `run` skill after loading it.

## Directives

- **Never add logic here.** This file is an alias only — all orchestration lives in `skills/run/SKILL.md`. If you find yourself writing steps here, move them to `run` instead.
- **Always pass arguments through unchanged.** If the caller passed `--experiments 5 --theme lint_warnings`, forward both flags verbatim when executing the `run` flow. Do not interpret or discard arguments at this layer.
- **Never invoke this skill recursively.** If `run` skill somehow delegates back to `autoimprove`, stop and report a routing loop.
- **Use this entry point only when the caller invokes the skill by name `autoimprove`.** If you are already inside the `run` flow, stay there — do not re-enter via this alias.
- **Do not use this skill to review results, inspect state, or roll back.** Use `report`, `status`, or `rollback` skills respectively.
