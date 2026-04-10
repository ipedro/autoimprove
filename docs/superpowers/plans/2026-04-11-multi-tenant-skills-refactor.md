# Multi-Tenant Skills Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix autoimprove plugin's multi-tenancy bug by replacing CWD-relative path references with `${CLAUDE_SKILL_DIR}` patterns, so skills work when invoked from any project's CWD, not just the autoimprove repo itself.

**Architecture:** Skills reference plugin-local helpers via `${CLAUDE_SKILL_DIR}` (provided by Claude Code v2.1.64+). Shared helpers move from `scripts/` to `skills/_shared/` for uniform one-hop sibling paths. SAFETY.md keeps its plugin-root location with a documented double-parent exception (read-only documents don't need uniformity). The `test` skill becomes a thin wrapper around `evaluate.sh --tests-only` (new flag).

**Tech Stack:** Bash, jq, Claude Code skill loader, autoimprove's existing test runner (`test/evaluate/test-evaluate.sh` with custom assertion framework).

**Reference spec:** `docs/superpowers/specs/2026-04-11-multi-tenant-skills-design.md` (commit a8c56ed).

---

## File Structure

### New files
- `skills/_shared/` (new directory) — replacement for `scripts/`
- `docs/superpowers/plans/2026-04-11-multi-tenant-skills-refactor.md` (this file)

### Files moved (git mv, content unchanged)
- `scripts/evaluate.sh` → `skills/_shared/evaluate.sh`
- `scripts/cleanup-worktrees.sh` → `skills/_shared/cleanup-worktrees.sh`
- `scripts/theme-weights.sh` → `skills/_shared/theme-weights.sh`
- `scripts/harvest.sh` → `skills/_shared/harvest.sh`
- `scripts/harvest-themes.sh` → `skills/_shared/harvest-themes.sh`
- `scripts/ar-write-round.sh` → `skills/_shared/ar-write-round.sh`

### Files modified
- `scripts/evaluate.sh` (before move) — add `--tests-only` flag
- `skills/test/SKILL.md` — rewrite as thin wrapper, drop legacy argument interface
- `skills/run/SKILL.md` — Step 0 SAFETY.md path + all `scripts/` references + `references/` reads
- `skills/run/references/loop.md` — all `scripts/` references in experiment loop steps
- `skills/cleanup/SKILL.md` — `scripts/cleanup-worktrees.sh` path
- `skills/rollback/SKILL.md` — `scripts/evaluate.sh` path (line 248)
- `skills/init/SKILL.md` — `scripts/evaluate.sh` paths (lines 237, 268). Note: `benchmark/metrics.sh` references are correct (target-project paths) and unchanged
- `skills/adversarial-review/SKILL.md` — `scripts/ar-write-round.sh` paths (lines 450, 454)
- `skills/calibrate/SKILL.md` — audit for any remaining plugin-local paths
- `autoimprove.yaml` — update `constraints.forbidden_paths` (replace `scripts/evaluate.sh` and `benchmark/**` if relevant; keep `SAFETY.md` entry; add `skills/_shared/**`)
- `test/evaluate/test-evaluate.sh` — add `=== Multi-tenant portability tests ===` section

### Files staying (intentionally NOT moved)
- `SAFETY.md` (plugin root) — read-only document, double-parent exception
- `skills/run/references/loop.md` and `tasktree.md` (skill-private content)
- `scripts/autoimprove-trigger.sh`, `scripts/install-hooks.sh`, `scripts/replay-pattern-layer.sh` (plugin infrastructure not called from skills)
- `scripts/score-challenge.sh` (used by challenge skill — audit during Phase 2 to confirm)
- All `benchmark/*.sh` (gate scripts, not directly called by skills)

---

## Phase 0 — Prerequisite Verification (HARD BLOCK)

**Why this exists:** the entire Q2 decision (use `skills/_shared/`) assumes Claude Code's skill loader ignores underscore-prefixed directories. If it tries to load `skills/_shared/` as a skill, the refactor's foundation collapses. This phase verifies the assumption before any file changes.

### Task 0.1: Test underscore-prefixed directory behavior

**Files:**
- Create: `skills/_shared/.keep` (placeholder)

- [ ] **Step 1: Create the placeholder directory and file**

```bash
mkdir -p skills/_shared
echo "Phase 0 prerequisite test — temporary file" > skills/_shared/.keep
ls -la skills/_shared/
```

Expected: directory exists with `.keep` inside.

- [ ] **Step 2: Reload plugins**

Tell the user (Pedro): "Ready to verify the prereq. Please run `/reload-plugins` in your Claude Code session, then tell me what the reload output reports — specifically whether it shows any errors mentioning `_shared` or whether the skill count changes unexpectedly."

Wait for Pedro's report.

- [ ] **Step 3: Verify _shared is not loaded as a skill**

After Pedro confirms reload happened, check the plugin's loaded skills via the `Skill` tool listing (or by asking Pedro to inspect the skill list). Verify:
- `_shared` does NOT appear as a skill name
- No load errors mention `skills/_shared/`
- The total skill count in the repo did NOT increase by 1 (it should be unchanged from before this commit)

- [ ] **Step 4: Decision gate**

If all 3 verifications pass: **PROCEED to Phase 1.** Delete the placeholder before commit (it'll be replaced by real content in Phase 2):

```bash
rm skills/_shared/.keep
rmdir skills/_shared
```

If ANY verification fails: **STOP. Do not proceed.** Revert the test:

```bash
rm -rf skills/_shared
```

Then escalate to Pedro: "Phase 0 verification failed. Claude Code does NOT ignore underscore-prefixed directories under skills/. The Q2 decision needs to be revisited — likely fall back to flat `scripts/` at plugin root with `${CLAUDE_SKILL_DIR}/../../scripts/` double-parent paths. Re-running brainstorming on Q2 may be needed."

---

## Phase 1 — Add `--tests-only` flag to `scripts/evaluate.sh`

**Why this exists:** the rewritten test skill (Phase 3) needs this flag to delegate. Adding it BEFORE moving the file means we can verify it works in-place against the existing test suite.

### Task 1.1: Write failing test for --tests-only flag

**Files:**
- Modify: `test/evaluate/test-evaluate.sh` (append a new test section near the end, before the `Results:` line)

- [ ] **Step 1: Locate the insertion point**

```bash
grep -n 'echo "Results:' test/evaluate/test-evaluate.sh
```

Expected: one line number, e.g. `547:echo "Results: $PASS passed, $FAIL failed"`. Tests must be inserted BEFORE this line.

- [ ] **Step 2: Add the failing test**

Insert this block immediately above the `echo "Results:"` line in `test/evaluate/test-evaluate.sh`:

```bash
echo ""
echo "=== --tests-only flag tests ==="

echo "--- Test: --tests-only runs gates and skips benchmarks ---"
tests_only_config='{"gates":[{"name":"trivial","command":"true"}],"benchmarks":[{"name":"should-be-skipped","command":"echo SHOULD_NOT_RUN >&2; echo {}","metrics":[{"name":"x","extract":"json:.x","direction":"higher_is_better"}]}],"regression_tolerance":0.02,"significance_threshold":0.01}'
tests_only_tmp=$(mktemp)
echo "$tests_only_config" > "$tests_only_tmp"
tests_only_out=$("$EVALUATE" --tests-only "$tests_only_tmp" /dev/null 2>&1)
tests_only_stderr=$("$EVALUATE" --tests-only "$tests_only_tmp" /dev/null 2>&1 1>/dev/null)
assert_json_field "tests-only mode marker" "$tests_only_out" '.mode' 'tests_only'
assert_json_field "tests-only gate ran" "$tests_only_out" '.gates[0].name' 'trivial'
assert_json_field "tests-only gate passed" "$tests_only_out" '.gates[0].passed' 'true'
# Verify benchmarks were NOT run — the benchmark would print SHOULD_NOT_RUN to stderr if it ran
if echo "$tests_only_stderr" | grep -q SHOULD_NOT_RUN; then
  echo "  FAIL: --tests-only ran benchmarks (saw SHOULD_NOT_RUN in stderr)"
  ((FAIL++)) || true
else
  echo "  PASS: --tests-only skipped benchmarks"
  ((PASS++)) || true
fi
rm -f "$tests_only_tmp"
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | grep -A5 'tests-only flag tests'
```

Expected output: failures because `--tests-only` is not yet recognized as a flag — the test will see normal evaluate output without `mode: tests_only`, and possibly the benchmark WILL run (printing `SHOULD_NOT_RUN`).

Confirm at least one assertion FAILS in the new section. If all PASS unexpectedly, the test is wrong — re-check the assertions before proceeding.

### Task 1.2: Implement --tests-only flag

**Files:**
- Modify: `scripts/evaluate.sh:9-25` (argument parsing block) and `scripts/evaluate.sh:298-326` (main body)

- [ ] **Step 1: Read the current argument parsing block**

```bash
sed -n '9,25p' scripts/evaluate.sh
```

Confirm the current parser handles `--include-llm-benchmarks` but not `--tests-only`.

- [ ] **Step 2: Add the flag to the argument parser**

Edit `scripts/evaluate.sh`. Find the block:

```bash
CONFIG=""
BASELINE="/dev/null"
INCLUDE_LLM_BENCHMARKS=false

for arg in "$@"; do
  case "$arg" in
    --include-llm-benchmarks) INCLUDE_LLM_BENCHMARKS=true ;;
    *)
      if [ -z "$CONFIG" ]; then
        CONFIG="$arg"
      elif [ "$BASELINE" = "/dev/null" ]; then
        BASELINE="$arg"
      fi
      ;;
  esac
done
```

Replace with:

```bash
CONFIG=""
BASELINE="/dev/null"
INCLUDE_LLM_BENCHMARKS=false
TESTS_ONLY=false

for arg in "$@"; do
  case "$arg" in
    --include-llm-benchmarks) INCLUDE_LLM_BENCHMARKS=true ;;
    --tests-only) TESTS_ONLY=true ;;
    *)
      if [ -z "$CONFIG" ]; then
        CONFIG="$arg"
      elif [ "$BASELINE" = "/dev/null" ]; then
        BASELINE="$arg"
      fi
      ;;
  esac
done
```

- [ ] **Step 3: Branch the main body on TESTS_ONLY**

Read `scripts/evaluate.sh` from line 285 to end:

```bash
sed -n '285,328p' scripts/evaluate.sh
```

Find the `# ── Main ──────...` block. The current main runs `run_gates`, then if gates passed runs `run_benchmarks` and emits a verdict. The fix: when `TESTS_ONLY=true`, run gates and emit a `tests_only` mode JSON, skip benchmarks.

Replace the main block:

```bash
# ── Main ──────────────────────────────────────────────────────────────────────

run_gates

if [ "$GATE_PASSED" = "false" ]; then
  failed_gate=$(echo "$GATE_RESULTS" | jq -r '.[-1].name')
  jq -n \
    --arg verdict "gate_fail" \
    --arg reason "gate '$failed_gate' failed" \
    --argjson gates "$GATE_RESULTS" \
    '{verdict: $verdict, reason: $reason, gates: $gates, metrics: {}, improved: [], regressed: [], verdict_logic: "gate_fast_fail"}'
  exit 0
fi

# tests-only mode — emit gates result and exit before benchmarks run
if [ "$TESTS_ONLY" = "true" ]; then
  jq -n \
    --argjson gates "$GATE_RESULTS" \
    '{mode: "tests_only", gates: $gates}'
  exit 0
fi

# All gates passed — run benchmarks
run_benchmarks
```

(Keep the rest of the main block — `INIT_MODE` branch, scoring branch — unchanged after this insertion.)

- [ ] **Step 4: Run the test to verify it now passes**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | grep -A10 'tests-only flag tests'
```

Expected: all 4 assertions in the new section PASS.

- [ ] **Step 5: Run the full test suite to verify no regressions**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | tail -3
```

Expected: `Results: <N> passed, 0 failed` where N is 442 + 4 (the new tests-only assertions) = 446.

If any test fails: do not proceed. Investigate the regression.

- [ ] **Step 6: Commit**

```bash
git add scripts/evaluate.sh test/evaluate/test-evaluate.sh
git commit -m "$(cat <<'EOF'
feat(evaluate): add --tests-only flag

Adds --tests-only to scripts/evaluate.sh that runs gates and exits
before benchmarks. Output mode "tests_only" with gates array only.

Enables the upcoming test skill rewrite to delegate to evaluate.sh
instead of duplicating gate-execution logic. Part of the multi-tenant
skills refactor (see docs/superpowers/plans/2026-04-11-multi-tenant-
skills-refactor.md).

Test suite: 442 -> 446 passing (4 new --tests-only assertions).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Phase 1 rollback

If anything goes wrong before commit:

```bash
git checkout scripts/evaluate.sh test/evaluate/test-evaluate.sh
```

If wrong AFTER commit, before pushing:

```bash
git reset --hard HEAD~1
```

---

## Phase 2 — Atomic move scripts/ → skills/_shared/

**Why this is one commit:** every reference to a moved script must update simultaneously. A partial commit would leave the repo in a broken state where some skills can't find their helpers.

### Task 2.1: Create skills/_shared/ and move the 6 scripts

**Files:**
- Move: `scripts/{evaluate,cleanup-worktrees,theme-weights,harvest,harvest-themes,ar-write-round}.sh` → `skills/_shared/`

- [ ] **Step 1: Verify no concurrent work in scripts/**

```bash
git status --short scripts/
```

Expected: empty (no uncommitted changes in scripts/).

- [ ] **Step 2: Create _shared/ and move the 6 scripts via git mv**

```bash
mkdir -p skills/_shared
git mv scripts/evaluate.sh skills/_shared/evaluate.sh
git mv scripts/cleanup-worktrees.sh skills/_shared/cleanup-worktrees.sh
git mv scripts/theme-weights.sh skills/_shared/theme-weights.sh
git mv scripts/harvest.sh skills/_shared/harvest.sh
git mv scripts/harvest-themes.sh skills/_shared/harvest-themes.sh
git mv scripts/ar-write-round.sh skills/_shared/ar-write-round.sh
ls skills/_shared/
```

Expected: 6 .sh files listed.

- [ ] **Step 3: Verify the OTHER scripts/ files were NOT moved**

```bash
ls scripts/
```

Expected: `autoimprove-trigger.sh`, `install-hooks.sh`, `replay-pattern-layer.sh`, `score-challenge.sh`, possibly `hooks/` directory. These remain in `scripts/`.

If `score-challenge.sh` exists, audit whether any skill references it:

```bash
grep -nE 'scripts/score-challenge' skills/
```

If any skill references it, add it to the move list above before proceeding.

### Task 2.2: Update internal cross-references inside the moved scripts

**Files:**
- Modify: `skills/_shared/evaluate.sh` if it references other scripts/
- Modify: `skills/_shared/harvest.sh` if it references other scripts/
- Modify: any other `skills/_shared/*.sh` if they reference each other

- [ ] **Step 1: Audit for cross-references between moved scripts**

```bash
grep -nE 'scripts/(evaluate|cleanup-worktrees|theme-weights|harvest|harvest-themes|ar-write-round)' skills/_shared/*.sh
```

Expected: ideally empty (the scripts shouldn't reference each other by relative path). If any are found, list them and continue to Step 2.

- [ ] **Step 2: Fix any cross-references using $SCRIPT_DIR self-location**

For each found reference, edit the script to use a self-relative path. Add this near the top of the file (after the shebang):

```bash
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

Then change references from `bash scripts/X.sh` to `bash "$SCRIPT_DIR/X.sh"`.

If no cross-references were found, skip this step entirely.

### Task 2.3: Update skill references to scripts/ → skills/_shared/

**Files:**
- Modify: `skills/run/SKILL.md` (multiple lines)
- Modify: `skills/run/references/loop.md` (multiple lines)
- Modify: `skills/cleanup/SKILL.md` (lines 38, 42, 52)
- Modify: `skills/rollback/SKILL.md` (line 248)
- Modify: `skills/init/SKILL.md` (lines 237, 268)
- Modify: `skills/adversarial-review/SKILL.md` (lines 450, 454)
- Modify: `skills/calibrate/SKILL.md` (audit for any remaining paths)

The substitution rule for each file:

| Old reference | New reference |
|---|---|
| `bash scripts/evaluate.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" ...` |
| `bash scripts/cleanup-worktrees.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh" ...` |
| `bash scripts/theme-weights.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/theme-weights.sh" ...` |
| `bash scripts/harvest.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/harvest.sh" ...` |
| `bash scripts/harvest-themes.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/harvest-themes.sh" ...` |
| `bash scripts/ar-write-round.sh ...` | `bash "${CLAUDE_SKILL_DIR}/../_shared/ar-write-round.sh" ...` |
| `test -f scripts/X.sh` | `test -f "${CLAUDE_SKILL_DIR}/../_shared/X.sh"` |
| `chmod +x scripts/X.sh scripts/Y.sh` | `chmod +x "${CLAUDE_SKILL_DIR}/../_shared/X.sh" "${CLAUDE_SKILL_DIR}/../_shared/Y.sh"` |

**Important:** prose mentions of `scripts/X.sh` (not in bash code blocks, just describing the file in the skill body) should ALSO update so the skill body is internally consistent and self-documenting.

- [ ] **Step 1: Update `skills/run/SKILL.md` Step 0 SAFETY.md path**

Find the line:

```
test -f SAFETY.md || { echo "FATAL: SAFETY.md not found at project root..."; exit 1; }
```

Replace with:

```
test -f "${CLAUDE_SKILL_DIR}/../../SAFETY.md" || { echo "FATAL: SAFETY.md not found at plugin root — this repo is incomplete or corrupted. Refusing to proceed without a safety contract."; exit 1; }
```

And the next line should already say "Then invoke the `Read` tool on `SAFETY.md`" — update it to `Then invoke the Read tool on "${CLAUDE_SKILL_DIR}/../../SAFETY.md"`.

- [ ] **Step 2: Update `skills/run/SKILL.md` references/ reads**

Find:

```
Read `references/loop.md` and `references/tasktree.md`, then execute the full experiment loop
```

Replace with:

```
Read `${CLAUDE_SKILL_DIR}/references/loop.md` and `${CLAUDE_SKILL_DIR}/references/tasktree.md`, then execute the full experiment loop
```

Also update the prose references at lines 555-556 if they point at `references/X.md`:

```bash
grep -nE 'references/(loop|tasktree)\.md' skills/run/SKILL.md
```

Update each prose reference to `${CLAUDE_SKILL_DIR}/references/X.md`.

- [ ] **Step 3: Update `skills/run/SKILL.md` scripts/ references**

```bash
grep -nE 'scripts/(evaluate|theme-weights|cleanup-worktrees|harvest|harvest-themes)' skills/run/SKILL.md
```

For each match, apply the substitution rule from the table above.

- [ ] **Step 4: Update `skills/run/references/loop.md`**

```bash
grep -nE 'scripts/(evaluate|cleanup-worktrees|harvest|harvest-themes|ar-write-round|theme-weights)' skills/run/references/loop.md
```

For each match, apply the substitution rule. Pay special attention to step 3i (evaluate.sh invocation), step 2f-ii and 4b-ii (cleanup-worktrees.sh sweeps), and step 2g (harvest.sh + harvest-themes.sh).

Also update the SAFETY.md inline-loading instruction in step 3g — change `read SAFETY.md from the project root` to `read SAFETY.md via "${CLAUDE_SKILL_DIR}/../../SAFETY.md"`.

- [ ] **Step 5: Update `skills/cleanup/SKILL.md`**

Find the prerequisites and invoke blocks. Replace:

```bash
test -f scripts/cleanup-worktrees.sh || {
  echo "FATAL: scripts/cleanup-worktrees.sh not found — are you in the autoimprove repo root?"
  exit 1
}
chmod +x scripts/cleanup-worktrees.sh
```

With:

```bash
test -f "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh" || {
  echo "FATAL: cleanup-worktrees.sh not found at \"${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh\" — plugin install is incomplete."
  exit 1
}
chmod +x "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh"
```

And the invoke block:

```bash
bash scripts/cleanup-worktrees.sh $ARGUMENTS
```

becomes:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh" $ARGUMENTS
```

- [ ] **Step 6: Update `skills/rollback/SKILL.md` line 248**

Find:

```bash
bash scripts/evaluate.sh experiments/evaluate-config.json experiments/rolling-baseline.json
```

Replace with:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" experiments/evaluate-config.json experiments/rolling-baseline.json
```

- [ ] **Step 7: Update `skills/init/SKILL.md` lines 237 and 268**

Find both occurrences of:

```bash
bash scripts/evaluate.sh experiments/evaluate-config.json /dev/null
```

Replace each with:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" experiments/evaluate-config.json /dev/null
```

**DO NOT** modify `benchmark/metrics.sh` references (lines 76, 125, 150, 171, 189, 205, 218, 336) — those are TARGET PROJECT paths that init creates in the user's repo, not plugin-local references. Leave them alone.

- [ ] **Step 8: Update `skills/adversarial-review/SKILL.md` lines 450, 454**

Find:

```bash
bash scripts/ar-write-round.sh "$RUN_DIR" <ROUND> "$ENTHUSIAST_TMP" "$ADVERSARY_TMP" "$JUDGE_TMP"
```

Replace with:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/ar-write-round.sh" "$RUN_DIR" <ROUND> "$ENTHUSIAST_TMP" "$ADVERSARY_TMP" "$JUDGE_TMP"
```

And the prose mention on line 454 — change `scripts/ar-write-round.sh writes` to `${CLAUDE_SKILL_DIR}/../_shared/ar-write-round.sh writes`.

- [ ] **Step 9: Audit `skills/calibrate/SKILL.md` for any remaining plugin-local references**

```bash
grep -nE '(scripts|benchmark|test|tests|references)/' skills/calibrate/SKILL.md
```

For each match, decide:
- If it's a plugin-local script reference → update with `${CLAUDE_SKILL_DIR}/../_shared/...`
- If it's a TARGET PROJECT path (e.g., where to write generated test files) → leave alone

- [ ] **Step 10: Update `autoimprove.yaml` constraints.forbidden_paths**

Find:

```yaml
constraints:
  forbidden_paths:
    - autoimprove.yaml
    - SAFETY.md                 # repo-local experimenter safety rules — never modify
    - scripts/evaluate.sh       # gate script is sacred
    - benchmark/**              # benchmark scripts are sacred
    - .claude-plugin/**
    - .claude/**
    - package.json
    - package-lock.json
```

Replace with:

```yaml
constraints:
  forbidden_paths:
    - autoimprove.yaml
    - SAFETY.md                 # repo-local experimenter safety rules — never modify
    - skills/_shared/**         # plugin-local helpers (formerly scripts/) are sacred
    - benchmark/**              # benchmark scripts are sacred
    - .claude-plugin/**
    - .claude/**
    - package.json
    - package-lock.json
```

(Keep `benchmark/**` because benchmark scripts are still in `benchmark/` — only the helper scripts moved.)

- [ ] **Step 11: Run the full test suite to verify no regressions**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | tail -3
```

Expected: `Results: 446 passed, 0 failed` (same count as Phase 1 commit).

If any test fails: investigate. The failure is most likely a missed reference somewhere.

- [ ] **Step 12: Run the AR effectiveness smoke gate**

```bash
bash tests/test-ar-effectiveness.sh 2>&1 | tail -3
```

Expected: `9/9 passed`.

- [ ] **Step 13: Run the no_padding gate**

```bash
bash benchmark/gate-no-padding.sh; echo "exit=$?"
```

Expected: `exit=0`.

- [ ] **Step 14: Verify scripts/ no longer contains the moved files**

```bash
ls scripts/
```

Expected: only `autoimprove-trigger.sh`, `install-hooks.sh`, `replay-pattern-layer.sh`, `score-challenge.sh` (or similar — depending on what was there before, MINUS the 6 moved files).

```bash
ls skills/_shared/
```

Expected: 6 .sh files.

- [ ] **Step 15: Commit the atomic move**

```bash
git add skills/_shared/ scripts/ skills/run/ skills/cleanup/ skills/rollback/ skills/init/ skills/adversarial-review/ skills/calibrate/ autoimprove.yaml
git status --short
```

Verify the staged diff includes:
- 6 deletions in `scripts/`
- 6 additions in `skills/_shared/`
- Modifications in 7 SKILL.md files + loop.md + autoimprove.yaml

Then:

```bash
git commit -m "$(cat <<'EOF'
fix(skills): move scripts/ → skills/_shared/ for multi-tenancy

Replaces all CWD-relative `scripts/X.sh` references in skills with
`${CLAUDE_SKILL_DIR}/../_shared/X.sh` (one-hop sibling path) so the
plugin works when invoked from any project's CWD, not just the
autoimprove repo itself.

Files moved (git mv, content unchanged):
- scripts/evaluate.sh           → skills/_shared/evaluate.sh
- scripts/cleanup-worktrees.sh  → skills/_shared/cleanup-worktrees.sh
- scripts/theme-weights.sh      → skills/_shared/theme-weights.sh
- scripts/harvest.sh            → skills/_shared/harvest.sh
- scripts/harvest-themes.sh     → skills/_shared/harvest-themes.sh
- scripts/ar-write-round.sh     → skills/_shared/ar-write-round.sh

Skills updated to use ${CLAUDE_SKILL_DIR}/../_shared/X.sh:
- skills/run/SKILL.md (Step 0 SAFETY.md path, scripts/ refs, references/ reads)
- skills/run/references/loop.md (all scripts/ refs in experiment loop)
- skills/cleanup/SKILL.md
- skills/rollback/SKILL.md
- skills/init/SKILL.md (plugin-local refs only — target-project paths unchanged)
- skills/adversarial-review/SKILL.md
- skills/calibrate/SKILL.md (audited)

SAFETY.md stays at plugin root with documented double-parent exception
${CLAUDE_SKILL_DIR}/../../SAFETY.md (read-only document, see spec Q3).

references/loop.md and tasktree.md stay co-located in skills/run/references/
with zero-hop ${CLAUDE_SKILL_DIR}/references/X.md (skill-private content,
see spec Q4).

constraints.forbidden_paths updated: scripts/evaluate.sh removed,
skills/_shared/** added.

Tests: 446/446 evaluate pass, 9/9 ar-effectiveness smoke pass, no_padding
gate passes.

Part of multi-tenant skills refactor (see plan
docs/superpowers/plans/2026-04-11-multi-tenant-skills-refactor.md and
spec docs/superpowers/specs/2026-04-11-multi-tenant-skills-design.md).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Phase 2 rollback

Before commit:

```bash
git checkout -- skills/ scripts/ autoimprove.yaml
git status --short  # should be clean for these paths
# Then move files back if needed:
git mv skills/_shared/evaluate.sh scripts/evaluate.sh  # etc.
rmdir skills/_shared
```

After commit, before push:

```bash
git reset --hard HEAD~1  # backs out the move commit
```

After push: file an issue and revert via `git revert <sha>`.

---

## Phase 3 — Rewrite `skills/test/SKILL.md` as thin wrapper

### Task 3.1: Read the current test skill body

**Files:**
- Read: `skills/test/SKILL.md`

- [ ] **Step 1: Capture the current frontmatter and content**

```bash
wc -l skills/test/SKILL.md
sed -n '1,30p' skills/test/SKILL.md
```

Note the current frontmatter (description, argument-hint, allowed-tools). The rewrite preserves the frontmatter shape but updates the argument-hint and replaces the body.

### Task 3.2: Rewrite the test skill body

**Files:**
- Modify: `skills/test/SKILL.md` — replace everything below the frontmatter `---` with the new body

- [ ] **Step 1: Update the frontmatter**

Edit `skills/test/SKILL.md` frontmatter. Change:

```yaml
argument-hint: "[challenge|integration|evaluate|harvest|agents|skills|all] [--quiet] [--test <name>]"
```

To:

```yaml
argument-hint: "[--quiet] [--gate <name>]"
```

Update the `description` field if it references the legacy suite arguments — generalize to:

```
description: "Use when running the autoimprove gate suite for the current project — runs all gates from autoimprove.yaml and reports pass/fail. Examples:

<example>
Context: User wants to verify all gates pass before running experiments.
user: \"run autoimprove tests\"
assistant: I'll use the test skill to run the gate suite from autoimprove.yaml and report results.
<commentary>Full gate run — test skill.</commentary>
</example>

<example>
Context: User wants to run only one gate by name.
user: \"run only the evaluate_tests gate\"
assistant: I'll use the test skill with --gate evaluate_tests.
<commentary>Filtered gate run — test skill.</commentary>
</example>"
```

- [ ] **Step 2: Replace the body with the thin wrapper**

Replace everything below the closing `---` of the frontmatter with:

```markdown
<SKILL-GUARD>
You are NOW executing the test skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Run the autoimprove gate suite for the current project by delegating to `evaluate.sh --tests-only`. The gates are read from `autoimprove.yaml gates:` in the project root, so this skill works for any project that has autoimprove configured.

## Parse arguments

Optional flags:
- `--quiet` — suppress per-gate output, show only the final summary line
- `--gate <name>` — filter to run only the named gate (must match an entry in `autoimprove.yaml gates:[].name`)

## Run

Verify the project has an autoimprove.yaml in CWD:

```bash
test -f autoimprove.yaml || {
  echo "FATAL: no autoimprove.yaml in current directory. The test skill must be invoked from the root of an autoimprove-configured project."
  exit 1
}
```

Verify the evaluate-config.json exists (generated by /autoimprove run, normally):

```bash
test -f experiments/evaluate-config.json || {
  echo "FATAL: experiments/evaluate-config.json not found. Run /autoimprove run first to generate it, or run /autoimprove init for a fresh project."
  exit 1
}
```

Invoke evaluate.sh in tests-only mode:

```bash
bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" --tests-only experiments/evaluate-config.json /dev/null
```

This emits a JSON document with `mode: "tests_only"` and a `gates: []` array containing each gate's name, passed flag, exit code, and duration.

## Filter and report

If `--gate <name>` was passed, parse the JSON output with `jq` to show only the matching gate:

```bash
RESULT=$(bash "${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh" --tests-only experiments/evaluate-config.json /dev/null)
if [ -n "$GATE_FILTER" ]; then
  RESULT=$(echo "$RESULT" | jq --arg name "$GATE_FILTER" '{mode: .mode, gates: [.gates[] | select(.name == $name)]}')
fi
```

If `--quiet` was passed, emit only:
```
N/M gates passed
```
where N = passing count, M = total count.

Otherwise, emit a per-gate breakdown:
```
=== Gate suite results ===
  PASS evaluate_tests       (18.5s)
  PASS ar_effectiveness_smoke (1.2s)
  PASS no_padding           (0.3s)

3/3 gates passed
```

## Exit code

Exit 0 if all gates passed. Exit 1 if any gate failed.

## When NOT to use

- **For benchmark scoring:** use `/autoimprove run` instead — that runs gates AND benchmarks AND scores them against baselines.
- **For manual experiment management:** use `/autoimprove experiment` (CRUD) or `/autoimprove rollback` (revert).
- **For session reports:** use `/autoimprove report`.

## Notes

- The legacy `[challenge|integration|evaluate|harvest|agents|skills|all]` argument interface from earlier versions of this skill has been removed. Those names were autoimprove-internal and never mapped cleanly onto user projects' gate names. Use `--gate <name>` to filter by actual gate names from your `autoimprove.yaml`.
- This skill delegates entirely to `${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh`. The dogfood case (autoimprove improving autoimprove) works because autoimprove's own `autoimprove.yaml gates:` already lists the right test commands.
```

- [ ] **Step 3: Verify the file is well-formed**

```bash
head -30 skills/test/SKILL.md
wc -l skills/test/SKILL.md
```

Expected: frontmatter intact, body starts with `<SKILL-GUARD>`, total length around 70-90 lines (down from much longer).

- [ ] **Step 4: Run the dogfood test suite to verify nothing else broke**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | tail -3
```

Expected: `Results: 446 passed, 0 failed`.

- [ ] **Step 5: Commit**

```bash
git add skills/test/SKILL.md
git commit -m "$(cat <<'EOF'
refactor(test): thin wrapper over evaluate.sh --tests-only

Rewrites skills/test/SKILL.md as a delegating wrapper around
`${CLAUDE_SKILL_DIR}/../_shared/evaluate.sh --tests-only`. The skill
now works for any project that has an autoimprove.yaml with gates:[]
defined, not just autoimprove itself.

Drops the legacy [challenge|integration|evaluate|harvest|agents|skills|
all] argument interface — those suite names were an abstraction leak
from autoimprove's internal layout and never mapped onto user-defined
gate names. New argument interface:
- no argument        → run all gates
- --quiet            → summary line only
- --gate <name>      → filter to one gate by name

Dogfood case still works: autoimprove's own autoimprove.yaml gates:[]
already lists bash test/evaluate/test-evaluate.sh,
bash tests/test-ar-effectiveness.sh, and bash benchmark/gate-no-padding.sh
which resolve correctly when invoked from autoimprove's own root.

Part of multi-tenant skills refactor (Decision Q1 in the spec).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Phase 3 rollback

Before commit:

```bash
git checkout -- skills/test/SKILL.md
```

After commit:

```bash
git reset --hard HEAD~1
```

---

## Phase 4 — Add multi-tenant portability tests

### Task 4.1: Add the env-var injection portability section

**Files:**
- Modify: `test/evaluate/test-evaluate.sh` (insert before the existing `Results:` line, after the --tests-only test section from Phase 1)

- [ ] **Step 1: Find the insertion point**

```bash
grep -n 'echo "Results:' test/evaluate/test-evaluate.sh
```

Note the line number. Tests must be inserted BEFORE this line.

- [ ] **Step 2: Add the portability test section**

Insert this block immediately before the `echo "Results:"` line:

```bash
echo ""
echo "=== Multi-tenant portability tests ==="

PLUGIN_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# Test: evaluate.sh works from non-plugin-root CWD via ${CLAUDE_SKILL_DIR} pattern
echo "--- Test: evaluate.sh runs from external CWD ---"
mt_tmp=$(mktemp -d)
mt_skill_dir="$PLUGIN_ROOT/skills/test"
# Minimal autoimprove.yaml with one trivial gate
cat > "$mt_tmp/autoimprove.yaml" <<EOF
gates:
  - name: trivial
    command: "true"
benchmarks: []
EOF
mkdir -p "$mt_tmp/experiments"
cat > "$mt_tmp/experiments/evaluate-config.json" <<EOF
{"gates":[{"name":"trivial","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}
EOF
mt_result=$(cd "$mt_tmp" && bash "$mt_skill_dir/../_shared/evaluate.sh" --tests-only experiments/evaluate-config.json /dev/null 2>&1)
mt_exit=$?
assert_eq "evaluate.sh exits 0 from external CWD" "0" "$mt_exit"
assert_json_field "evaluate.sh emits tests_only mode" "$mt_result" '.mode' 'tests_only'
assert_json_field "trivial gate ran" "$mt_result" '.gates[0].name' 'trivial'
assert_json_field "trivial gate passed" "$mt_result" '.gates[0].passed' 'true'
rm -rf "$mt_tmp"

# Test: cleanup-worktrees.sh works from non-plugin-root CWD
echo "--- Test: cleanup-worktrees.sh runs from external CWD ---"
mt_tmp=$(mktemp -d)
cd "$mt_tmp"
git init -q -b main 2>/dev/null || git init -q
git config user.email "portability@test.local"
git config user.name "portability"
echo "seed" > README.md
git add README.md && git commit -q -m "seed"
mt_skill_dir="$PLUGIN_ROOT/skills/cleanup"
mt_result=$(bash "$mt_skill_dir/../_shared/cleanup-worktrees.sh" 2>&1)
mt_exit=$?
assert_eq "cleanup-worktrees.sh exits 0 on clean repo from external CWD" "0" "$mt_exit"
if echo "$mt_result" | grep -q '\[cleanup\] 0 worktrees, 0 branches removed'; then
  echo "  PASS: cleanup summary line present"
  ((PASS++)) || true
else
  echo "  FAIL: cleanup summary line missing (got: $mt_result)"
  ((FAIL++)) || true
fi
cd "$PLUGIN_ROOT"
rm -rf "$mt_tmp"

# Test: theme-weights.sh works from non-plugin-root CWD
echo "--- Test: theme-weights.sh runs from external CWD ---"
mt_tmp=$(mktemp -d)
cd "$mt_tmp"
cat > autoimprove.yaml <<EOF
themes:
  auto:
    strategy: weighted_random
    cooldown_per_theme: 3
    priorities:
      test_coverage: 1
      skill_quality: 2
EOF
mkdir -p experiments
echo -e "id\ttimestamp\ttheme\tverdict\timproved_metrics\tregressed_metrics\ttokens\twall_time\tcommit_msg" > experiments/experiments.tsv
mt_skill_dir="$PLUGIN_ROOT/skills/run"
mt_result=$(bash "$mt_skill_dir/../_shared/theme-weights.sh" 2>/dev/null)
mt_exit=$?
assert_eq "theme-weights.sh exits 0 from external CWD" "0" "$mt_exit"
if echo "$mt_result" | jq -e '.test_coverage' >/dev/null 2>&1; then
  echo "  PASS: theme-weights output is valid JSON with theme keys"
  ((PASS++)) || true
else
  echo "  FAIL: theme-weights output not valid JSON or missing theme keys (got: $mt_result)"
  ((FAIL++)) || true
fi
cd "$PLUGIN_ROOT"
rm -rf "$mt_tmp"
```

This adds 3 portability test sections covering 3 representative scripts. The pattern can be extended to other scripts later if needed.

- [ ] **Step 3: Run the test suite to verify the new tests pass**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | grep -A20 'Multi-tenant portability'
```

Expected: all portability assertions PASS.

- [ ] **Step 4: Run the full suite for total count**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | tail -3
```

Expected: `Results: <N> passed, 0 failed` where N = 446 + 8 (the new portability assertions) = 454. Adjust the expected count based on the exact assertions you added.

- [ ] **Step 5: Commit**

```bash
git add test/evaluate/test-evaluate.sh
git commit -m "$(cat <<'EOF'
test(evaluate): add multi-tenant portability section

Adds env-var injection tests that simulate the external-user CWD
scenario deterministically — cd to mktemp dir, set up minimal config,
invoke each refactored script via the new ${CLAUDE_SKILL_DIR}/../_shared/
pattern, assert exit 0 + expected output.

Covers 3 representative scripts:
- evaluate.sh --tests-only
- cleanup-worktrees.sh
- theme-weights.sh

These tests catch the exact failure class that Session 25's dogfood
testing missed: scripts that work from plugin-root CWD but break when
invoked from any other directory.

Reuses existing test/evaluate/test-evaluate.sh runner — no new test
infrastructure. Part of multi-tenant skills refactor (Decision Q5 in
the spec).

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>
EOF
)"
```

### Phase 4 rollback

Before commit:

```bash
git checkout -- test/evaluate/test-evaluate.sh
```

After commit:

```bash
git reset --hard HEAD~1
```

---

## Phase 5 — Manual end-to-end verification

**Why this exists:** Phase 4's env-var injection tests validate OUR use of `${CLAUDE_SKILL_DIR}` (passing it as a shell variable). They do NOT validate that Claude Code's own skill loader correctly substitutes the variable when invoking the skill via the `Skill` tool. Phase 5 closes that gap with one manual test.

### Task 5.1: Reload plugins

- [ ] **Step 1: Ask Pedro to reload plugins**

Tell Pedro: "Phases 1-4 are committed. Please run `/reload-plugins` and confirm it succeeds (no errors mentioning skills/_shared/ or any of the moved scripts)."

Wait for Pedro's confirmation.

### Task 5.2: Invoke a refactored skill from a non-plugin-root CWD

- [ ] **Step 1: Tell Pedro to test the cleanup skill from /tmp**

Tell Pedro: "Now please cd to a directory that is NOT the autoimprove repo and is NOT the plugin install dir — for example `cd /tmp && mkdir test-mt && cd test-mt && git init`. Then invoke `/autoimprove cleanup --dry-run`. Report what happens — specifically whether the skill finds the cleanup-worktrees.sh script and runs it, or whether it errors with FATAL or path-not-found."

- [ ] **Step 2: Verify the result**

Expected: the cleanup skill finds `${CLAUDE_SKILL_DIR}/../_shared/cleanup-worktrees.sh` (resolved by Claude Code's substitution to the plugin's actual install path), runs it against the temp git repo, and reports `[cleanup] 0 worktrees, 0 branches removed` (since the temp repo has no orphans). Exit code 0.

If anything fails: investigate. Possibilities:
- Claude Code didn't substitute `${CLAUDE_SKILL_DIR}` → Phase 0 verification was wrong, fall back to flat scripts/ pattern
- The plugin install symlink is stale → tell Pedro to run `/install-local-plugin` and try again
- The skill body has a typo → fix and re-test

### Task 5.3: Test the rewritten test skill from a non-plugin-root CWD

- [ ] **Step 1: Set up a minimal external project**

Tell Pedro to run, in his /tmp/test-mt directory:

```bash
cat > autoimprove.yaml <<EOF
gates:
  - name: trivial
    command: "true"
benchmarks: []
themes:
  auto:
    strategy: weighted_random
    cooldown_per_theme: 3
    priorities:
      test_coverage: 1
EOF
mkdir -p experiments
cat > experiments/evaluate-config.json <<EOF
{"gates":[{"name":"trivial","command":"true"}],"benchmarks":[],"regression_tolerance":0.02,"significance_threshold":0.01}
EOF
```

- [ ] **Step 2: Invoke the test skill**

Tell Pedro: "From /tmp/test-mt, invoke `/autoimprove test`. Report what happens — should run the trivial gate and report `1/1 gates passed`."

- [ ] **Step 3: Verify**

Expected: `1/1 gates passed` (or `PASS trivial`). Exit 0.

If it fails: same investigation path as 5.2.

### Task 5.4: Cleanup the test directory

- [ ] **Step 1: Tell Pedro to clean up**

Tell Pedro: "Manual smoke complete. You can remove /tmp/test-mt now: `rm -rf /tmp/test-mt`."

---

## Phase 6 — Push and final verification

### Task 6.1: Verify all phase commits are present

- [ ] **Step 1: Check the commit history**

```bash
git log --oneline -10
```

Expected (most recent at top):
- `test(evaluate): add multi-tenant portability section`
- `refactor(test): thin wrapper over evaluate.sh --tests-only`
- `fix(skills): move scripts/ → skills/_shared/ for multi-tenancy`
- `feat(evaluate): add --tests-only flag`
- (older commits below)

If any are missing, do not push. Re-run the missing phase.

### Task 6.2: Run the full test suite one last time

- [ ] **Step 1: Full test suite**

```bash
bash test/evaluate/test-evaluate.sh 2>&1 | tail -3
bash tests/test-ar-effectiveness.sh 2>&1 | tail -3
bash benchmark/gate-no-padding.sh; echo "exit=$?"
```

Expected:
- evaluate: `Results: 454 passed, 0 failed` (or whatever the final count is — it should be ≥ 446 + the new portability tests)
- ar-effectiveness: `9/9 passed`
- no_padding: `exit=0`

### Task 6.3: Push to main

- [ ] **Step 1: Push**

```bash
git push 2>&1 | tail -5
```

Expected: push succeeds (may show "Bypassed rule violations" warning per the org's bypass-protected-branch policy; that's normal for direct main pushes).

- [ ] **Step 2: Verify remote is up to date**

```bash
git log --oneline origin/main..HEAD
```

Expected: empty (remote and local are in sync).

---

## Self-Review (run after writing the plan)

1. **Spec coverage:** Every spec decision Q1-Q5 is implemented?
   - Q1 (test skill rewrite): ✓ Phase 1 (--tests-only flag) + Phase 3 (skill rewrite)
   - Q2 (skills/_shared/): ✓ Phase 0 (prereq) + Phase 2 (atomic move)
   - Q3 (SAFETY.md at root): ✓ Phase 2 Step 1 (Step 0 path update with double-parent)
   - Q4 (references/ co-located): ✓ Phase 2 Step 2 (zero-hop ${CLAUDE_SKILL_DIR}/references/)
   - Q5 (env-var injection tests): ✓ Phase 4
   - Manual smoke: ✓ Phase 5
   - Push: ✓ Phase 6

2. **Placeholder scan:** No TBDs, no "implement later", no "similar to Task N", no "appropriate error handling" hand-waves. ✓

3. **Type consistency:** Path patterns are uniform throughout — `${CLAUDE_SKILL_DIR}/../_shared/X.sh` for shared, `${CLAUDE_SKILL_DIR}/../../SAFETY.md` for SAFETY exception, `${CLAUDE_SKILL_DIR}/references/X.md` for skill-private references. ✓

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-04-11-multi-tenant-skills-refactor.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch a fresh subagent per task, review between tasks, fast iteration

**2. Inline Execution** — execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?

---

## Notes

- **Phase 0 is a hard block.** If Claude Code does not ignore underscore-prefixed directories under `skills/`, this entire plan needs to be revisited. Do not proceed past Phase 0 without verification.
- **The atomic Phase 2 commit** is the highest-risk step. It touches 7+ files. Run all 3 test suites before committing. If anything fails, rollback is `git reset --hard HEAD~1` (only if not yet pushed).
- **Phase 5 (manual smoke) requires Pedro's active participation.** The agent cannot test from a non-plugin-root CWD on its own — it needs Pedro to actually invoke `/autoimprove cleanup` from a different directory in his real Claude Code session.
- **Out-of-scope items** (cross-tenant state file pollution, declarative safety rules rewrite, automated multi-tenant test harness) are flagged in the spec and remain as separate future issues. Do NOT expand scope during execution.
