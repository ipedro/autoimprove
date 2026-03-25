---
name: run
description: "Start an autoimprove experiment session. Runs the autonomous improvement loop."
arguments:
  - name: experiments
    description: "Maximum number of experiments to run (overrides autoimprove.yaml)"
    required: false
  - name: theme
    description: "Run only this specific theme instead of weighted random"
    required: false
---

Start an autoimprove session using the orchestrator skill.

Read `autoimprove.yaml` from the project root. If it doesn't exist, suggest running `/autoimprove init` first.

{{#if experiments}}Override `max_experiments_per_session` with {{experiments}}.{{/if}}
{{#if theme}}Override theme selection to only use theme: {{theme}}.{{/if}}

Use the orchestrator skill to run the experiment loop.
