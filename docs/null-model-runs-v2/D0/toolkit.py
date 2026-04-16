#!/usr/bin/env python3
"""D0 Null-Model Validation Toolkit v2 — Fix A + Fix B.

Fix A (solo-only ranking): H5 counts wins among SOLO cells (1-3) only.
Fix B (per-rerun permutation): option ordering randomized per rerun to
eliminate primacy bias.

Per-rerun, a seeded permutation maps labels A/B/C to semantic options
(morning, afternoon, evening). Listing order in "All Options" follows
label order (A, B, C) always — we randomize which SEMANTIC option each
label represents, so position-1 = A in every prompt but A's meaning
varies per rerun.

H5 aggregation uses SEMANTIC category of the winning solo cell, via
permutation lookup.
"""

import json, re, sys, os, math, random
from pathlib import Path
from collections import Counter

# ─── D0 Domain Config ───────────────────────────────────────────────────────

PROBLEM = "Choose the optimal deploy window for a web service"

ENVIRONMENT_BLOCK = """Team is 8 engineers in a single time zone. No external SLAs tied to deploy windows.
CI takes 12 minutes. Rollback takes 3 minutes. No global traffic patterns worth
mentioning — traffic distribution across the day is flat within 10%.
No users report time-of-day preferences."""

# Semantic options (fixed meanings, independent of permutation)
SEMANTIC_OPTIONS = {
    "morning":   "Deploy on weekday mornings (9am-12pm)",
    "afternoon": "Deploy on weekday afternoons (1pm-5pm)",
    "evening":   "Deploy on weekday evenings (6pm-9pm)",
}

# Combo descriptions are derived per-rerun from the permutation.
# Alts are fixed (don't participate in primacy-relevant labeling).
ALTS = {
    8: ("D", "Deploy during midday transition period (11am-2pm)"),
    9: ("E", "Deploy at an ad-hoc time chosen day-of by the team"),
}

BANNED_TOKENS = ["standup", "lunch", "traffic", "on-call", "monitoring", "rollback"]
CATEGORIES = ["morning", "afternoon", "evening", "other"]
REQUIRED_DIMS = {"feasibility", "risk", "synergy_potential", "implementation_cost"}

INFRA_SUFFIXES = [
    "daemon", "service", "queue", "cluster", "database", "pipeline", "mesh",
    "cache", "replica", "server", "proxy", "gateway", "broker", "scheduler",
    "worker", "pool", "container", "instance", "node", "registry", "store",
    "vault", "bucket", "vm",
]

RESULTS_DIR = Path("/tmp/null-model-runs-v2/D0")

# ─── Fix B: Per-rerun permutation ──────────────────────────────────────────

_ALL_PERMS = [
    ["morning", "afternoon", "evening"],
    ["morning", "evening", "afternoon"],
    ["afternoon", "morning", "evening"],
    ["afternoon", "evening", "morning"],
    ["evening", "morning", "afternoon"],
    ["evening", "afternoon", "morning"],
]

# Pre-registered balanced design: 20 reruns.
# Blocks 1-3: each block uses all 6 perms (18 reruns, perfectly balanced:
#   each label-semantic pairing appears exactly 6 times).
# Reruns 19-20: 2 bonus permutations from index [0, 3] for diagnostic — adds
#   light imbalance (morning+A: 7, afternoon+A: 7, evening+A: 6 — max diff 1).
_PRE_REGISTERED_SEQUENCE = (
    [0, 1, 2, 3, 4, 5]  # block 1
    + [2, 4, 0, 5, 1, 3]  # block 2 (shuffled order, still all 6 perms)
    + [5, 3, 1, 4, 2, 0]  # block 3 (shuffled order, still all 6 perms)
    + [0, 3]              # bonus reruns 19, 20
)

assert len(_PRE_REGISTERED_SEQUENCE) == 20


def permutation_for_rerun(rerun: int) -> list[str]:
    """Return the semantic ordering of (A, B, C) labels for this rerun.

    Uses a pre-registered balanced sequence of 20 permutations. Each of the 6
    possible permutations appears 3 times in reruns 1-18; reruns 19-20 are
    bonus perms giving max label-semantic-pairing imbalance of 1 across 20 reruns.
    """
    assert 1 <= rerun <= 20
    return list(_ALL_PERMS[_PRE_REGISTERED_SEQUENCE[rerun - 1]])


def option_for_label(rerun: int, label: str) -> str:
    """Semantic key (morning/afternoon/evening) for a given label in this rerun."""
    perm = permutation_for_rerun(rerun)
    return perm["ABC".index(label)]


def description_for_label(rerun: int, label: str) -> str:
    """Human-readable option description (semantic)."""
    return SEMANTIC_OPTIONS[option_for_label(rerun, label)]


def cells_for_rerun(rerun: int) -> dict[int, tuple[str, str]]:
    """Return {cell_num: (label, description)} for all 9 cells in this rerun."""
    perm = permutation_for_rerun(rerun)
    a_desc = SEMANTIC_OPTIONS[perm[0]]
    b_desc = SEMANTIC_OPTIONS[perm[1]]
    c_desc = SEMANTIC_OPTIONS[perm[2]]

    # Combo descriptions — "Combined {x}-and-{y} window" using semantic labels
    def combo_desc(keys: list[str]) -> str:
        readable = {"morning": "morning", "afternoon": "afternoon", "evening": "evening"}
        windows = [readable[k] for k in keys]
        return f"Combined deploy window covering {' and '.join(windows)} hours"

    cells = {
        1: ("A", a_desc),
        2: ("B", b_desc),
        3: ("C", c_desc),
        4: ("A+B", combo_desc([perm[0], perm[1]])),
        5: ("A+C", combo_desc([perm[0], perm[2]])),
        6: ("B+C", combo_desc([perm[1], perm[2]])),
        7: ("A+B+C", combo_desc([perm[0], perm[1], perm[2]])),
        8: ALTS[8],
        9: ALTS[9],
    }
    return cells


# ─── Prompt Generation ──────────────────────────────────────────────────────

TEMPLATE = """CRITICAL: Do NOT invoke any tools. Answer only from this prompt. Return JSON immediately.

You are scoring a design option for the following problem.

## Problem
{problem}

## Available Infrastructure / Environment
{environment}

## All Options Under Consideration
A: {opt_a}
B: {opt_b}
C: {opt_c}

## Option Under Evaluation
Cell {cell_num}: {label} — {description}

## SCORING CONVENTION (MANDATORY — HIGHER=BETTER on ALL dimensions)

You MUST score EXACTLY these four dimensions, using these EXACT keys. Do not add,
rename, or omit any. Your output will be schema-validated and rejected if the
dimension keys do not match.

- feasibility: 1 showstopper → 10 trivial to build
- risk: 1 highest risk → 10 lowest risk / most robust (HIGHER = SAFER)
- synergy_potential: 1 incompatible → 10 composes cleanly
- implementation_cost: 1 days of work → 10 minutes

## Output (JSON only, no prose, no fences)

{{"cell": {cell_num}, "label": "{label}", "risk_direction_used": "higher_safer", "scores": {{"feasibility": <int 1-10>, "risk": <int 1-10>, "synergy_potential": <int 1-10>, "implementation_cost": <int 1-10>}}, "composite": <mean of the 4 scores>, "mechanism_novelty": "<one sentence; no banned tokens; commit to one mechanism, no hedging>", "dealbreaker": null or "<one sentence; if risk is based on infrastructure, only cite infrastructure explicitly listed in the Environment block above>"}}

Your "scores" object must contain EXACTLY those 4 keys. Any other keys cause
rejection and re-dispatch. Do not include correctness, complexity, robustness,
token_efficiency, coordination_power, debuggability, failure_isolation,
leverage, novelty, composability, runtime_safety, latency_impact, reliability,
observability_gain, operational_complexity, security_surface, safety,
hook_coverage, or any other dimension. Four dimensions. Named exactly as above."""


def generate_prompt(rerun: int, cell_num: int) -> str:
    cells = cells_for_rerun(rerun)
    label, desc = cells[cell_num]
    return TEMPLATE.format(
        problem=PROBLEM,
        environment=ENVIRONMENT_BLOCK,
        opt_a=description_for_label(rerun, "A"),
        opt_b=description_for_label(rerun, "B"),
        opt_c=description_for_label(rerun, "C"),
        cell_num=cell_num,
        label=label,
        description=desc,
    )


def generate_retry_prompt(rerun: int, cell_num: int, failure_reason: str) -> str:
    base = generate_prompt(rerun, cell_num)
    preamble = (
        f"RETRY — your previous output was rejected: {failure_reason}. "
        "Fix ONLY the issue described. Return valid JSON immediately.\n\n"
    )
    return preamble + base


# ─── Validation (7 gates per §3.1) ─────────────────────────────────────────

def _cites_unlisted_infra(dealbreaker: str, env_text: str) -> bool:
    env_lower = env_text.lower()
    words = dealbreaker.lower().split()
    for word in words:
        clean = re.sub(r'[^a-z-]', '', word)
        for suffix in INFRA_SUFFIXES:
            if clean.endswith(suffix) and clean not in env_lower:
                if not re.search(rf'\b{re.escape(clean)}\b', env_lower):
                    return True
    return False


def validate(cell_output_str: str) -> tuple[str, dict | None]:
    try:
        obj = json.loads(cell_output_str)
    except (json.JSONDecodeError, TypeError):
        return "parse_fail", None

    scores = obj.get("scores", {})
    if not isinstance(scores, dict):
        return "schema_fail", None
    if set(scores.keys()) != REQUIRED_DIMS:
        return "schema_fail", None

    if obj.get("risk_direction_used") != "higher_safer":
        return "convention_fail", None

    for k, v in scores.items():
        if not isinstance(v, int) or not (1 <= v <= 10):
            return "score_type_fail", None

    obj["composite"] = sum(scores.values()) / 4.0

    output_text = " ".join([
        obj.get("mechanism_novelty", "") or "",
        obj.get("dealbreaker", "") or "",
    ]).lower()
    for token in BANNED_TOKENS:
        if re.search(rf"\b{re.escape(token.lower())}\b", output_text):
            return f"banned_token_fail:{token}", None

    db = (obj.get("dealbreaker") or "").lower().strip()
    if db and db != "null" and _cites_unlisted_infra(db, ENVIRONMENT_BLOCK):
        return "infra_grounding_fail", None

    return "ok", obj


# ─── Results Tracking ───────────────────────────────────────────────────────

def save_cell_result(rerun: int, cell: int, status: str, obj: dict | None,
                     raw: str, attempt: int):
    d = RESULTS_DIR / f"rerun-{rerun:02d}"
    d.mkdir(parents=True, exist_ok=True)
    result = {
        "rerun": rerun,
        "cell": cell,
        "status": status,
        "attempt": attempt,
        "raw_output": raw,
        "parsed": obj,
    }
    (d / f"cell-{cell}.json").write_text(json.dumps(result, indent=2))


def save_rerun_summary(rerun: int):
    d = RESULTS_DIR / f"rerun-{rerun:02d}"
    cells = []
    ok_count = 0
    dropped_count = 0
    for c in range(1, 10):
        f = d / f"cell-{c}.json"
        if f.exists():
            data = json.loads(f.read_text())
            cells.append(data)
            if data["status"] == "ok":
                ok_count += 1
            else:
                dropped_count += 1
        else:
            dropped_count += 1
            cells.append({"cell": c, "status": "missing"})

    valid = dropped_count == 0

    # Fix A: compute SOLO winner (cells 1-3 only)
    solo_composites = []
    for c in cells:
        if c.get("cell") in (1, 2, 3) and c.get("status") == "ok" and c.get("parsed"):
            solo_composites.append((c["cell"], c["parsed"]["composite"], c["parsed"]["label"]))

    solo_winner_cell = None
    solo_winner_label = None
    solo_winner_composite = None
    solo_tie = False

    if len(solo_composites) == 3:
        solo_composites.sort(key=lambda x: -x[1])
        top_cell, top_val, top_label = solo_composites[0]
        near_top = [(c, v, l) for c, v, l in solo_composites if abs(v - top_val) <= 0.001]
        if len(near_top) >= 2:
            solo_tie = True
        else:
            solo_winner_cell = top_cell
            solo_winner_label = top_label
            solo_winner_composite = top_val

    # Fix B: resolve winner label to semantic category via permutation
    solo_winner_category = None
    if solo_winner_label:
        solo_winner_category = option_for_label(rerun, solo_winner_label)

    # Also compute overall-9-cell winner for diagnostic (prior protocol)
    overall_composites = []
    for c in cells:
        if c.get("status") == "ok" and c.get("parsed"):
            overall_composites.append((c["cell"], c["parsed"]["composite"], c["parsed"]["label"]))

    overall_winner_cell = None
    overall_winner_label = None
    overall_tie = False
    if overall_composites:
        overall_composites.sort(key=lambda x: -x[1])
        top_cell, top_val, top_label = overall_composites[0]
        near_top = [(c, v, l) for c, v, l in overall_composites if abs(v - top_val) <= 0.001]
        if len(near_top) >= 2:
            overall_tie = True
        else:
            overall_winner_cell = top_cell
            overall_winner_label = top_label

    summary = {
        "rerun": rerun,
        "permutation": permutation_for_rerun(rerun),
        "ok_cells": ok_count,
        "dropped_cells": dropped_count,
        "valid": valid,
        # Fix A + Fix B (authoritative for H5)
        "solo_winner_cell": solo_winner_cell,
        "solo_winner_label": solo_winner_label,
        "solo_winner_composite": solo_winner_composite,
        "solo_winner_category": solo_winner_category,
        "solo_tie": solo_tie,
        # Diagnostic (prior protocol, not used for H5)
        "overall_winner_cell": overall_winner_cell,
        "overall_winner_label": overall_winner_label,
        "overall_tie": overall_tie,
    }
    (d / "summary.json").write_text(json.dumps(summary, indent=2))
    return summary


# ─── Statistics (H5 Fix A + Fix B, H6, H7) ─────────────────────────────────

def _log_comb(n, k):
    return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1)


def _binomtest(k, n, p):
    pval = 0.0
    for i in range(k, n + 1):
        log_prob = _log_comb(n, i) + i * math.log(p) + (n - i) * math.log(1 - p)
        pval += math.exp(log_prob)
    return pval


def compute_stats():
    total_cells = 0
    ok_cells = 0
    total_reruns = 20
    valid_reruns = 0
    summaries = []

    for r in range(1, 21):
        d = RESULTS_DIR / f"rerun-{r:02d}"
        summary_f = d / "summary.json"
        if summary_f.exists():
            s = json.loads(summary_f.read_text())
            summaries.append(s)
            if s["valid"]:
                valid_reruns += 1
            for c in range(1, 10):
                total_cells += 1
                cf = d / f"cell-{c}.json"
                if cf.exists():
                    cd = json.loads(cf.read_text())
                    if cd["status"] == "ok":
                        ok_cells += 1

    h6_rate = ok_cells / 180 if total_cells > 0 else 0
    h7_rate = valid_reruns / 20

    # H5: count solo-winner semantic categories across 20 reruns
    solo_categories = []
    for s in summaries:
        cat = s.get("solo_winner_category") or "other"
        solo_categories.append(cat)

    cat_counts = Counter(solo_categories)
    most_common_cat = cat_counts.most_common(1)[0] if cat_counts else (None, 0)
    d0_target_count = most_common_cat[1]

    h5_pvalue = _binomtest(d0_target_count, 20, 0.25) if d0_target_count > 0 else 1.0
    h5_pass = h5_pvalue >= 0.0125

    # Diagnostic: position bias (wins per cell number among solo winners)
    position_counts = Counter()
    for s in summaries:
        if s.get("solo_winner_cell"):
            position_counts[s["solo_winner_cell"]] += 1

    # Diagnostic: label bias (wins per label A/B/C among solo winners)
    label_counts = Counter()
    for s in summaries:
        if s.get("solo_winner_label"):
            label_counts[s["solo_winner_label"]] += 1

    results = {
        "domain": "D0",
        "fix_a": True,
        "fix_b": True,
        "total_cells_dispatched": total_cells,
        "ok_cells": ok_cells,
        "h6_rate": round(h6_rate, 4),
        "h6_pass": h6_rate >= 0.80,
        "valid_reruns": valid_reruns,
        "total_reruns": 20,
        "h7_rate": round(h7_rate, 4),
        "h7_pass": h7_rate >= 0.80,
        "category_counts": dict(cat_counts),
        "most_frequent_category": most_common_cat[0] if most_common_cat[0] else None,
        "most_frequent_count": d0_target_count,
        "h5_pvalue": round(h5_pvalue, 6),
        "h5_pass": h5_pass,
        "h5_interpretation": (
            "PASS — uniformity not rejected (null model clean under Fix A+B)"
            if h5_pass else
            "FAIL — dominant category emerged (null model still poisoned, ABORT)"
        ),
        "diagnostic_position_counts": dict(position_counts),
        "diagnostic_label_counts": dict(label_counts),
        "summaries": summaries,
    }

    (RESULTS_DIR / "d0-stats.json").write_text(json.dumps(results, indent=2))
    return results


# ─── CLI ─────────────────────────────────────────────────────────────────────

def main():
    if len(sys.argv) < 2:
        print("Usage:")
        print("  toolkit.py prompt <rerun> <cell>")
        print("  toolkit.py retry <rerun> <cell> <reason>")
        print("  toolkit.py validate <json_string>")
        print("  toolkit.py process-cell-file <rerun> <cell> <attempt> <raw_file>")
        print("  toolkit.py summary <rerun>")
        print("  toolkit.py stats")
        print("  toolkit.py gen-all")
        print("  toolkit.py perm <rerun>")
        sys.exit(1)

    cmd = sys.argv[1]

    if cmd == "prompt":
        print(generate_prompt(int(sys.argv[2]), int(sys.argv[3])))

    elif cmd == "retry":
        print(generate_retry_prompt(int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]))

    elif cmd == "validate":
        raw = sys.argv[2]
        status, obj = validate(raw)
        print(json.dumps({"status": status, "parsed": obj}))

    elif cmd == "process-cell-file":
        rerun = int(sys.argv[2])
        cell = int(sys.argv[3])
        attempt = int(sys.argv[4])
        raw_path = sys.argv[5]
        raw = Path(raw_path).read_text().strip()
        # Try to extract JSON from output
        json_match = re.search(r'\{[^{}]*"cell"[^{}]*"scores"[^{}]*\{[^{}]*\}[^{}]*\}', raw, re.DOTALL)
        raw_json = json_match.group(0) if json_match else raw
        status, obj = validate(raw_json)
        save_cell_result(rerun, cell, status, obj, raw_json, attempt)
        print(json.dumps({"status": status, "cell": cell, "rerun": rerun, "attempt": attempt}))

    elif cmd == "summary":
        s = save_rerun_summary(int(sys.argv[2]))
        print(json.dumps(s, indent=2))

    elif cmd == "stats":
        r = compute_stats()
        print(json.dumps(r, indent=2))

    elif cmd == "perm":
        r = int(sys.argv[2])
        print(json.dumps({
            "rerun": r,
            "permutation": permutation_for_rerun(r),
            "A_semantic": option_for_label(r, "A"),
            "B_semantic": option_for_label(r, "B"),
            "C_semantic": option_for_label(r, "C"),
        }, indent=2))

    elif cmd == "gen-all":
        for rerun in range(1, 21):
            d = RESULTS_DIR / "prompts" / f"rerun-{rerun:02d}"
            d.mkdir(parents=True, exist_ok=True)
            for c in range(1, 10):
                (d / f"cell-{c}.txt").write_text(generate_prompt(rerun, c))
        print("Wrote prompts for 20 reruns × 9 cells = 180 files.")

    else:
        print(f"Unknown command: {cmd}")
        sys.exit(1)


if __name__ == "__main__":
    main()
