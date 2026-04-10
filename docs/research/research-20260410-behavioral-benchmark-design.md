# Behavioral Benchmark Design — val_bpb analog for skills

**Date:** 2026-04-10
**Status:** ⚠️ **PHASE 1 SUPERSEDED** after Codex adversarial review (same day) — see "Post-Review Update" section below before reading the original design. The original design has a fatal anti-gaming flaw. Do NOT implement Phase 1 as written.
**Owner:** TBD
**Prior art:** karpathy/autoresearch (`~/Developer/autoresearch`)

---

## ⚠️ Post-Review Update — READ FIRST

This design note was written in the same session as the karpathy investigation that motivated it. High risk of echo-chamber errors. A Codex adversarial review was dispatched immediately after drafting and found a **fatal architectural flaw** that invalidates Phase 1 as originally specified.

**The original design is preserved below the horizontal rule for historical/learning value (retire-in-place pattern).** Do not implement it as written.

### The fatal flaw: fixtures are visible to the skill at inference time

The original design claims `skill_behavioral_score` is the autoimprove analog of karpathy's `val_bpb`. This is wrong in a specific, important way.

**Karpathy's protection (`prepare.py:43`):** the validation shard is a pinned constant. The training path never touches it. The agent cannot modify `prepare.py`. The model cannot see validation data during training. The metric is structurally un-gameable because the only way to improve it is to actually improve the model.

**My design's flaw:** fixture prompts are loaded into the Claude agent's context at inference time. The skill being tested literally sees the fixture wording as part of its input. **An experimenter modifying the skill can pattern-match the fixture wording and write a skill that games that specific task without generalizing.**

`skill_behavioral_score` is NOT structurally un-gameable the way `val_bpb` is. "Behavioral measurement" alone is insufficient — **concealment** is the other half of the anti-gaming guarantee.

### Concrete attack on the `cleanup` fixture

The original design proposed:
- task_prompt: `"Clean up the test worktrees"`
- success_criterion: `"worktree count reduced to 0"`

Attack path an experimenter could take:
1. Modify `skills/cleanup/SKILL.md` to detect the literal string `"Clean up the test worktrees"` in its invocation context
2. Instruct Claude to run `rm -rf .git/worktrees/*` when that trigger is seen
3. Fixture reports success — worktree count IS reduced to 0 (satisfied the literal criterion)
4. Skill is now destructive — it nukes git metadata instead of safely removing worktrees via the guarded helper
5. Benchmark keeps the experiment, rolling baseline "improves", the skill is now actively harmful to the repo

This attack is simpler than the structural gaming attacks I was worried about, and my design has zero defense against it. The blind-experimenter pattern doesn't save us because the fixture prompt arrives through the normal skill invocation path — it's not "scoring data" that can be hidden, it's the input itself.

### Other Codex findings that invalidate parts of the original

1. **Default model mismatch:** the original fixture schema defaults `baseline_model: haiku` / `treatment_model: haiku`, but the actual default experimenter in `autoimprove.yaml budget.experimenter_model` is `sonnet`. Measuring haiku's response to a skill is not evidence of how sonnet (the real experimenter) will use it.

2. **`run` fixture is trivially gameable:** the proposed criterion "new TSV row with an allowed verdict" is satisfied by any experimenter that appends a valid-looking row without running a real experiment.

3. **`idea-matrix` fixture would repeat a prior failure:** the original matrix-effectiveness.sh benchmark fell back to word-count and label-counting rather than semantic checking. "9 valid cell JSON objects" as a criterion is satisfiable by structurally valid but vacuous or duplicated cells.

4. **`diagnose` regex criterion is brittle:** "output contains (race condition|missing lock|null deref)" false-fails on semantically correct paraphrases like "concurrent access without synchronization".

5. **Phase 1 "~2 days" estimate is unrealistic:** no `run_frequency` field exists in the evaluate.sh schema, `llm-judge` benchmarks are documented as periodic-only (not per-session as I claimed), and the closest existing reference implementations (`benchmark/ar-effectiveness.sh`, `benchmark/matrix-effectiveness.sh`) are ad-hoc shells with fuzzy matching and heuristics — not reusable infrastructure.

6. **Fixture authoring + maintenance cost is unestimated.** The original design asserts "fixtures can be authored faster than skills evolve" without supporting evidence. This is recurring maintenance work, not one-time setup.

7. **Minor autoresearch misread:** the original claims karpathy's eval is "purely runtime behavioral." Correct, but the design summary omits the simplicity criterion (`program.md:37`) which is an explicit qualitative keep/discard factor beyond raw score, AND omits the VRAM soft constraint documented in `program.md`. Doesn't invalidate the core reframing but the comparison is less precise than stated.

### Revised path forward

The original Phase 1 → Phase 4 plan is replaced with:

**Phase 0 (new, prerequisite): Benchmarkability audit.** For each of autoimprove's ~25 skills, classify as:
- **`artifact-state deterministic`** — success can be checked by inspecting filesystem/git/TSV state after invocation (example: `cleanup` — "was the worktree actually removed, including proper git worktree prune").
- **`structured-output deterministic`** — success is a regex/schema check on the skill's output AND the check is non-trivial to satisfy via prompt overfitting (harder category).
- **`semantic / LLM-judge`** — success requires understanding, cannot be deterministically verified. These skills CANNOT be fixtured safely; keep them out of any automated benchmark.

Output: `docs/research/research-20260411-benchmarkability-audit.md` or similar. Expected outcome: most skills fall into category 3 and are NOT fixturable.

**Phase 1 (revised): Single-fixture pilot — `cleanup` ONLY + red-team attack test.**

Scope:
- Write ONE fixture for `skills/cleanup` with a success criterion that checks BOTH "worktree count reduced" AND "git worktree prune was actually run" (not just metadata deletion) AND "no git-internal files outside worktree dirs were touched"
- Run the fixture against the current cleanup skill (establishes baseline)
- **Explicit red-team attack test:** manually write an adversarial version of cleanup.md that tries to game the fixture (the `rm -rf .git/worktrees/*` attack, or variants). Run it. If the adversarial skill scores highly, the fixture is broken — fix the success criterion before proceeding.
- Run the real cleanup skill 5 times and measure score variance. If variance > some threshold (TBD), the signal is too noisy to gate on.
- **Do NOT wire into evaluate.sh or the grind loop.** This is a manual pilot to validate that fixture-based measurement can even work, not a production benchmark.

Budget: one human day of focused work including writing the adversarial test. If the adversarial test succeeds at fooling the fixture, abort and rethink the category — do not try to patch the criterion under deadline pressure.

**Phase 2 (conditional on Phase 1 success): Add concealment if possible.**
- **Fixture rotation:** every grind session gets a randomly-selected fixture variant from a pool. Experimenter cannot pattern-match a specific wording because the wording changes.
- **Parameterized fixtures:** task prompt is a template with random parameters (e.g., random number of worktrees, random branch names). Experimenter cannot hardcode values.
- **Red-team the rotation:** another manual attack test. Can the experimenter pattern-match the template structure instead of literal text?

If neither concealment approach defeats the red-team → abandon fixture-based benchmarks for skill_quality. LLM-judge as periodic-only (weekly, not session-level, not gating) becomes the next-best option.

**Phase 3 (very conditional): Wire into grind loop.**
- Only after at least 2 skills have passed Phase 1 + Phase 2 red-team tests independently
- Shadow mode first (computed, not gating) for 3 sessions
- Only then promote to gate

### What Codex recommended and I'm adopting verbatim

> **Don't build.** Do a benchmarkability audit first: classify each skill as `artifact-state deterministic`, `structured-output deterministic`, or `semantic/LLM-judge`. Run a manual non-gating pilot for `cleanup` only, including an explicit overfitting attack test. Keep LLM-based quality checks periodic until at least two fixtures are demonstrably stable across repeated runs and resistant to prompt overfitting.

### The meta-lesson

The original design was produced in the same session as the insight that motivated it. High self-reinforcement risk. Codex reading autoresearch + design + existing benchmarks independently caught what I couldn't. **Major architectural reframes produced in a single session should always be stress-tested with an independent model before implementation, no exceptions.** The 30-minute Codex review prevented 2-3 hours of engineering on a gameable design.

See MAGI: `patterns/behavioral_benchmark_held_out_fixture_problem.md` for the fuller investigation record.

---

## Original Design (preserved below, DO NOT implement Phase 1 as specified)

Everything below this line is the original design as written before the Codex review. Preserved for learning value and to document what was tried. See the Post-Review Update above for the corrections.

## TL;DR

autoimprove's 13 deterministic metrics are mostly structural (line-counting regex proxies). karpathy's autoresearch — the original inspiration — uses **one** behavioral metric: `val_bpb` measured by running the model against a pinned held-out shard. The metric is un-gameable because it measures runtime behavior, not artifact structure.

We validated the structural approach against the `superpowers` plugin (gold-standard reference) and found 3 of 4 prompt-quality metrics are anti-quality — autoimprove scores HIGHER than the gold standard on "higher is better" metrics. The grind loop has been optimizing away from narrative-rich quality.

This note specifies the replacement: a behavioral benchmark for skills that invokes each skill on a fixed test task and measures outcome against a pinned success criterion.

## Why structural metrics fail for skill quality

**The artifact vs behavior gap.** Structural metrics (`imperative_ratio`, `example_density`, etc.) measure properties of the SKILL.md text itself — line counts, regex matches, section presence. They're cheap and deterministic but measure the wrong thing. A skill's value is whether it makes Claude produce better outputs when invoked, not whether its prose has high directive density.

**Superpowers skills prove the point.** `using-superpowers.md` (the flagship introduction skill) scores 0.0000 on our current `imperative_ratio` benchmark. The gold standard fails our quality gate. That's the reductio.

**Every structural metric becomes a Goodhart target eventually.** Pattern-grep can be satisfied by pasting patterns. Line-counts can be inflated. Even LLM-based rubric scoring (the Rubric Escalation Ladder idea) is structural — it scores artifact properties, not behavior.

## What karpathy did right

Single metric: `val_bpb` (validation bits-per-byte). Computed by running the model on a pinned validation shard and taking `total_nats / (log(2) * total_bytes)`. The metric is:

1. **Behavioral** — runs the actual artifact (the trained model) on held-out data
2. **Un-gameable by structure** — no way to improve it without making the model actually predict better
3. **Single number** — no composite scoring, no dimension aggregates
4. **Tied to an immutable eval harness** — `prepare.py` is declared read-only (`program.md:28-31`)

The experimenter is NOT blind to the score. Karpathy shows it after every run (`grep "^val_bpb:" run.log`, `program.md:100`). Blindness is unnecessary because the metric is structurally un-gameable.

## The analog for skills: `skill_behavioral_score`

### Core design

For each skill, define a **fixture** — a `(task, success_criterion)` pair that represents what the skill is supposed to help with. The benchmark:

1. Spawns a Claude agent with the test task and WITHOUT the skill loaded → record baseline output
2. Spawns another Claude agent with the test task and WITH the skill loaded → record treatment output
3. Evaluates both against the success criterion deterministically
4. Metric = `treatment_success_rate - baseline_success_rate` (bounded [-1, 1])
5. Aggregate across all skill fixtures: `mean(skill_behavioral_score)` is the single gate metric

Higher is better. A skill that makes outputs worse produces a negative delta — immediate red flag. A skill that has no effect produces ~0 — drives the aggregate down, signaling useless skills.

### Why this satisfies the autoresearch pattern

- **Behavioral:** measures actual Claude outputs, not the skill's text
- **Un-gameable structurally:** the experimenter can make the skill look as directive/imperative/bulleted as it wants — the metric only cares whether the skill helps Claude solve the task
- **Single number at the gate layer** (even though computed per-skill)
- **Pinned eval harness:** fixtures go in a read-only location (`benchmark/skill-fixtures/`) treated as sacred like karpathy's `prepare.py`

### What to fixture

Each skill needs a minimal fixture. Examples:

| Skill | Fixture task | Success criterion |
|---|---|---|
| `skills/diagnose` | "Given a failing test output, identify the root cause" (fed fixed output) | Output contains specific root-cause string |
| `skills/idea-matrix` | "Score 3 options for X" (fed fixed problem) | Output contains 9 valid cell JSON objects |
| `skills/cleanup` | "Clean up the test worktrees" (fed fixed git state) | Worktree count reduced to 0 |
| `skills/run` | "Run 1 experiment on theme X" | `experiments.tsv` has 1 new row, verdict is one of {keep, neutral, regress, gate_fail} |

Not every skill needs a fixture on day one. Start with the high-value ones — skills actually modified in recent experiments.

### Cost control (the reason this was removed before)

The previous behavioral benchmarks (`ar-effectiveness.sh`, `matrix-effectiveness.sh`) were removed in 2026-03-30 because they spawned claude CLI sessions per experiment → minutes per run, burned token pools, broke Haiku grinds. We must not repeat that.

Mitigations:

1. **Run 1x per session, not per experiment.** Use the `run_frequency: session` field (new — add to `evaluate-config.json` schema).
2. **Only fixture changed skills.** If experiment N only touched `skills/cleanup/SKILL.md`, run only the cleanup fixture, not all 25.
3. **Cache baseline outputs.** Rerun baseline only when epoch baseline refreshes, not per experiment. The (task, no-skill) output is a fixed reference.
4. **Budget cap:** max 2 fixture invocations per experiment. Hard ceiling.
5. **Haiku by default for the fixture runs.** Sonnet only if signal is ambiguous.
6. **Deterministic success criteria.** Avoid LLM-judge loops. The success criterion is a regex or a shell command checking artifact state, not another LLM call.

### Schema changes

Add to `autoimprove.yaml` benchmarks:

```yaml
  - name: skill-behavioral
    type: llm-judge
    run_frequency: session   # NEW: "experiment" | "session"
    command: bash benchmark/skill-behavioral.sh
    metrics:
      - name: skill_behavioral_score
        extract: "json:.skill_behavioral_score"
        direction: higher_is_better
        tolerance: 0.05
        significance: 0.05
```

Add to `scripts/evaluate.sh` benchmark runner:

- Read `run_frequency` field; if "session" and experiment is not first of session, skip and use last cached result
- Add `benchmark/skill-fixtures/` to the sacred path list (human-edit-only)
- Integrate with budget-check skill to abort if weekly budget < 40%

Add new files:

- `benchmark/skill-behavioral.sh` — orchestrator for the fixture loop
- `benchmark/skill-fixtures/<skill-name>.yaml` — one per fixtured skill
- `benchmark/skill-fixtures/README.md` — fixture authoring guide (human-facing)

### Fixture schema

```yaml
# benchmark/skill-fixtures/diagnose.yaml
skill: skills/diagnose
task_prompt: |
  You are debugging a failing test. Here is the output:
  <FIXED TEST OUTPUT>
  Identify the root cause in one sentence.
success_criterion:
  type: regex
  pattern: "(race condition|missing lock|null deref)"
baseline_model: haiku
treatment_model: haiku
timeout_seconds: 60
```

### Pilot plan

Phase 1 (~2 days): implement `skill-behavioral.sh` + fixture schema + 3 pilot fixtures (diagnose, cleanup, idea-matrix). Run manually, not wired to grind loop. Validate that the same skill scored across 5 runs produces consistent results.

Phase 2 (~1 day): wire into `evaluate.sh` as a session-level benchmark. Integrate with budget-check. Run in shadow mode (computed but not gating) for 3 sessions to collect calibration data.

Phase 3 (~1 day): promote to gate. Tighten tolerance based on pilot variance.

Phase 4 (ongoing): add fixtures for more skills as they become grind targets.

## Open questions

1. **Determinism.** Even with temperature=0, Claude outputs vary slightly. Does single-run-per-fixture produce stable scores, or do we need N=3 and take median? Pilot will tell.

2. **Baseline drift.** If we update the baseline_model between sessions, baseline outputs shift, which shifts the delta. Should baseline be pinned to a specific model version for the lifetime of a fixture? Probably yes.

3. **Negative deltas.** What if removing a skill IMPROVES Claude's output on some task? That's a real outcome worth surfacing — not a bug, a signal that the skill is net-harmful.

4. **Fixture rot.** If a skill evolves, does its fixture still measure the right thing? Fixtures need versioning and explicit review cadence.

5. **What about agents and commands?** The same pattern applies. Scope Phase 1-3 to skills only, extend to agents/commands later.

## What this replaces

After Phase 3, delete these metrics from `autoimprove.yaml`:
- `trigger_precision` (the last structural prompt-quality metric — even the "right-pointing" one is still structural)
- `skill_doc_coverage` (already broken per session 25 debug, returns 0 due to BSD grep)
- `agent_completeness` (structural, untested against gold standard)

Keep:
- `test_count`, `broken_constraints`, `broken_refs` — these ARE behavioral-ish (test suite state)
- `revert_rate`, `bug_escape_rate`, `ar_severity_trend`, `fix_durability` — reliability metrics, domain-appropriate

## References

- `~/Developer/autoresearch/program.md` lines 28-37, 100-109 — karpathy's eval + anti-gaming philosophy
- `~/Developer/autoresearch/prepare.py` lines 344-365 — `evaluate_bpb` implementation
- MAGI note `patterns/autoresearch_behavioral_vs_structural_metrics.md` — the investigation that produced this design
- MAGI note `patterns/imperative_ratio_empirical_anti_quality.md` — the empirical failure that triggered the investigation
- MAGI note `decisions/imperative_ratio_fix_decision.md` — the idea-matrix trail
- Commit `1a0bf5e fix(config): remove imperative_ratio metric` — the first delete
- Commit `40c42b2 Revert "fix(experimenter): codify skill_quality directive-ratio pattern"` — the companion revert

## Status & next actions

This document is the `val_bpb` analog DESIGN. Implementation is not started. Before implementing:

1. Pedro approval on the overall direction
2. Decide which skills get fixtures in Phase 1
3. Decide whether the existing `benchmark/ar-effectiveness.sh` / `matrix-effectiveness.sh` can be repurposed as pilot fixtures (they're still in the repo)
4. Sketch success criteria for the pilot fixtures to avoid LLM-judge-in-the-loop
