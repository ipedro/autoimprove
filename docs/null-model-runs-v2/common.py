#!/usr/bin/env python3
"""Shared toolkit for null-model validation — v10.2 with Fix A + Fix B.

Used by domain-specific toolkits (D1, D2, D3) via import. D0 has its own
standalone toolkit at /tmp/null-model-runs-v2/D0/toolkit.py (already complete).

Usage from a domain toolkit:
    from common import (
        generate_prompt, generate_retry_prompt, validate,
        save_cell_result, save_rerun_summary, compute_stats,
        permutation_for_rerun, option_for_label, cells_for_rerun,
    )

    DOMAIN_CONFIG = { ... }  # see DOMAIN_CONFIGS below
    init_domain(DOMAIN_CONFIG, results_dir="/tmp/null-model-runs-v2/D1")
"""
import json, re, sys, math
from pathlib import Path
from collections import Counter

# ─── Shared Constants ──────────────────────────────────────────────────────

REQUIRED_DIMS = {"feasibility", "risk", "synergy_potential", "implementation_cost"}

INFRA_SUFFIXES = [
    "daemon", "service", "queue", "cluster", "database", "pipeline", "mesh",
    "cache", "replica", "server", "proxy", "gateway", "broker", "scheduler",
    "worker", "pool", "container", "instance", "node", "registry", "store",
    "vault", "bucket", "vm",
]

# ─── Pre-registered balanced permutation sequence (Fix B) ──────────────────
#
# 6 permutations of (pos_0, pos_1, pos_2) over 3 semantic keys. A domain's
# 3 semantic keys are identified by the order in DOMAIN_CONFIG["options"].
# Block design: 20 reruns = 3 full blocks of 6 perms + 2 bonus.
# Each (label, semantic_idx) pairing appears 6 or 7 times (max diff = 1).

_ALL_PERMS_IDX = [
    (0, 1, 2),
    (0, 2, 1),
    (1, 0, 2),
    (1, 2, 0),
    (2, 0, 1),
    (2, 1, 0),
]

_PRE_REGISTERED_SEQUENCE = (
    [0, 1, 2, 3, 4, 5]
    + [2, 4, 0, 5, 1, 3]
    + [5, 3, 1, 4, 2, 0]
    + [0, 3]
)

assert len(_PRE_REGISTERED_SEQUENCE) == 20


# ─── Runtime Domain Binding ────────────────────────────────────────────────

_DOMAIN = None
_RESULTS_DIR = None


def init_domain(config: dict, results_dir: str):
    """Set the active domain config and results directory.

    config keys:
      - id: "D1" | "D2" | "D3"
      - problem: str
      - environment: str
      - options: dict[str, str]  — ordered {semantic_key: description}; len == 3
      - categories: list[str]    — 4 MEE categories per protocol §2
      - target_category: str     — the pre-registered target (one of categories)
      - banned_tokens: list[str]
      - alts: dict[int, tuple[str, str]]  — {8: (label, desc), 9: (label, desc)}
    """
    global _DOMAIN, _RESULTS_DIR
    assert isinstance(config["options"], dict)
    assert len(config["options"]) == 3, "v10.2 supports exactly 3 options per domain"
    _DOMAIN = config
    _RESULTS_DIR = Path(results_dir)
    _RESULTS_DIR.mkdir(parents=True, exist_ok=True)


def _semantic_keys() -> list[str]:
    return list(_DOMAIN["options"].keys())


def permutation_for_rerun(rerun: int) -> list[str]:
    """Return the semantic key ordering for (A, B, C) labels in this rerun."""
    assert 1 <= rerun <= 20
    keys = _semantic_keys()
    idx_perm = _ALL_PERMS_IDX[_PRE_REGISTERED_SEQUENCE[rerun - 1]]
    return [keys[i] for i in idx_perm]


def option_for_label(rerun: int, label: str) -> str:
    """Semantic key for label A/B/C in this rerun."""
    perm = permutation_for_rerun(rerun)
    return perm["ABC".index(label)]


def description_for_label(rerun: int, label: str) -> str:
    return _DOMAIN["options"][option_for_label(rerun, label)]


def cells_for_rerun(rerun: int) -> dict[int, tuple[str, str]]:
    """{cell_num: (label, description)} for all 9 cells in this rerun."""
    perm = permutation_for_rerun(rerun)
    a_desc = _DOMAIN["options"][perm[0]]
    b_desc = _DOMAIN["options"][perm[1]]
    c_desc = _DOMAIN["options"][perm[2]]

    # Combo descriptions — readable composite names
    def combo_desc(keys: list[str]) -> str:
        descs = [_DOMAIN["options"][k] for k in keys]
        names = ", ".join(descs)
        return f"Hybrid combining: {names}"

    cells = {
        1: ("A", a_desc),
        2: ("B", b_desc),
        3: ("C", c_desc),
        4: ("A+B", combo_desc([perm[0], perm[1]])),
        5: ("A+C", combo_desc([perm[0], perm[2]])),
        6: ("B+C", combo_desc([perm[1], perm[2]])),
        7: ("A+B+C", combo_desc([perm[0], perm[1], perm[2]])),
        8: _DOMAIN["alts"][8],
        9: _DOMAIN["alts"][9],
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
        problem=_DOMAIN["problem"],
        environment=_DOMAIN["environment"],
        opt_a=description_for_label(rerun, "A"),
        opt_b=description_for_label(rerun, "B"),
        opt_c=description_for_label(rerun, "C"),
        cell_num=cell_num,
        label=label,
        description=desc,
    )


def generate_retry_prompt(rerun: int, cell_num: int, reason: str) -> str:
    base = generate_prompt(rerun, cell_num)
    return (
        f"RETRY — your previous output was rejected: {reason}. "
        "Fix ONLY the issue described. Return valid JSON immediately.\n\n"
    ) + base


# ─── Validation ────────────────────────────────────────────────────────────

def _cites_unlisted_infra(dealbreaker: str, env_text: str) -> bool:
    env_lower = env_text.lower()
    for word in dealbreaker.lower().split():
        clean = re.sub(r'[^a-z-]', '', word)
        for suffix in INFRA_SUFFIXES:
            if clean.endswith(suffix) and clean not in env_lower:
                if not re.search(rf'\b{re.escape(clean)}\b', env_lower):
                    return True
    return False


def validate(raw: str) -> tuple[str, dict | None]:
    try:
        obj = json.loads(raw)
    except (json.JSONDecodeError, TypeError):
        return "parse_fail", None

    scores = obj.get("scores", {})
    if not isinstance(scores, dict):
        return "schema_fail", None
    if set(scores.keys()) != REQUIRED_DIMS:
        return "schema_fail", None

    if obj.get("risk_direction_used") != "higher_safer":
        return "convention_fail", None

    for v in scores.values():
        if not isinstance(v, int) or not (1 <= v <= 10):
            return "score_type_fail", None

    obj["composite"] = sum(scores.values()) / 4.0

    text = " ".join([obj.get("mechanism_novelty") or "", obj.get("dealbreaker") or ""]).lower()
    for token in _DOMAIN["banned_tokens"]:
        if re.search(rf"\b{re.escape(token.lower())}\b", text):
            return f"banned_token_fail:{token}", None

    db = (obj.get("dealbreaker") or "").lower().strip()
    if db and db != "null" and _cites_unlisted_infra(db, _DOMAIN["environment"]):
        return "infra_grounding_fail", None

    return "ok", obj


# ─── Persistence ──────────────────────────────────────────────────────────

def save_cell_result(rerun: int, cell: int, status: str, obj: dict | None, raw: str, attempt: int):
    d = _RESULTS_DIR / f"rerun-{rerun:02d}"
    d.mkdir(parents=True, exist_ok=True)
    (d / f"cell-{cell}.json").write_text(json.dumps({
        "rerun": rerun, "cell": cell, "status": status, "attempt": attempt,
        "raw_output": raw, "parsed": obj,
    }, indent=2))


def save_rerun_summary(rerun: int) -> dict:
    d = _RESULTS_DIR / f"rerun-{rerun:02d}"
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

    # Fix A: solo-only ranking (cells 1-3)
    solo = []
    for c in cells:
        if c.get("cell") in (1, 2, 3) and c.get("status") == "ok" and c.get("parsed"):
            solo.append((c["cell"], c["parsed"]["composite"], c["parsed"]["label"]))

    swc = swl = swcomp = swcat = None
    stie = False
    if len(solo) == 3:
        solo.sort(key=lambda x: -x[1])
        top_cell, top_val, top_label = solo[0]
        near = [(x[0], x[1], x[2]) for x in solo if abs(x[1] - top_val) <= 0.001]
        if len(near) >= 2:
            stie = True
        else:
            swc, swcomp, swl = top_cell, top_val, top_label
            swcat = option_for_label(rerun, swl)

    summary = {
        "rerun": rerun,
        "domain": _DOMAIN["id"],
        "permutation": permutation_for_rerun(rerun),
        "ok_cells": ok_count,
        "dropped_cells": dropped_count,
        "valid": valid,
        "solo_winner_cell": swc,
        "solo_winner_label": swl,
        "solo_winner_composite": swcomp,
        "solo_winner_category": swcat,  # semantic key (e.g., "out-of-process-shared")
        "solo_tie": stie,
    }
    (d / "summary.json").write_text(json.dumps(summary, indent=2))
    return summary


# ─── Statistics ────────────────────────────────────────────────────────────

def _log_comb(n, k):
    return math.lgamma(n + 1) - math.lgamma(k + 1) - math.lgamma(n - k + 1)


def _binomtest(k, n, p):
    pval = 0.0
    for i in range(k, n + 1):
        pval += math.exp(_log_comb(n, i) + i * math.log(p) + (n - i) * math.log(1 - p))
    return pval


def compute_stats() -> dict:
    total_cells = 0
    ok_cells = 0
    valid_reruns = 0
    summaries = []

    for r in range(1, 21):
        d = _RESULTS_DIR / f"rerun-{r:02d}"
        f = d / "summary.json"
        if f.exists():
            s = json.loads(f.read_text())
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

    h6_rate = ok_cells / 180
    h7_rate = valid_reruns / 20

    # Count winning SEMANTIC categories (from solo winners).
    # Map the semantic key to its protocol category via DOMAIN["semantic_to_category"].
    # For D0 the semantic key IS the category (morning/afternoon/evening/other). For D1-D3,
    # we need the mapping from option semantic to its MEE category.
    cat_map = _DOMAIN.get("semantic_to_category", {})
    cat_counts = Counter()
    for s in summaries:
        sem = s.get("solo_winner_category")
        if sem is None:
            cat_counts["other"] += 1
        else:
            cat_counts[cat_map.get(sem, sem)] += 1

    most_common_cat = cat_counts.most_common(1)[0] if cat_counts else (None, 0)
    most_cat_name = most_common_cat[0]
    most_cat_n = most_common_cat[1]

    target_cat = _DOMAIN.get("target_category")
    target_count = cat_counts.get(target_cat, 0) if target_cat else 0

    # H1 (target-category threshold 14/20) — only defined if target_category present
    h1_pass = None
    if target_cat:
        h1_pass = target_count >= 14

    # H3 (uniformity test on target_count vs p0=0.25) — only if target present
    h3_pvalue = None
    h3_pass = None
    if target_cat:
        h3_pvalue = _binomtest(target_count, 20, 0.25)
        h3_pass = h3_pvalue < 0.0125

    # H5 (null test — most frequent vs p0=0.25) — only for D0 (no target)
    h5_pvalue = None
    h5_pass = None
    if not target_cat:
        h5_pvalue = _binomtest(most_cat_n, 20, 0.25) if most_cat_n > 0 else 1.0
        h5_pass = h5_pvalue >= 0.0125

    # Diagnostic: position/label wins among solo winners
    pos_counts = Counter()
    lbl_counts = Counter()
    sem_counts = Counter()
    for s in summaries:
        if s.get("solo_winner_cell"):
            pos_counts[s["solo_winner_cell"]] += 1
            lbl_counts[s["solo_winner_label"]] += 1
            sem_counts[s["solo_winner_category"]] += 1

    results = {
        "domain": _DOMAIN["id"],
        "fix_a": True, "fix_b": True,
        "total_cells_dispatched": total_cells,
        "ok_cells": ok_cells,
        "h6_rate": round(h6_rate, 4),
        "h6_pass": h6_rate >= 0.80,
        "valid_reruns": valid_reruns,
        "total_reruns": 20,
        "h7_rate": round(h7_rate, 4),
        "h7_pass": h7_rate >= 0.80,
        "category_counts": dict(cat_counts),
        "most_frequent_category": most_cat_name,
        "most_frequent_count": most_cat_n,
        "target_category": target_cat,
        "target_count": target_count,
        "h1_pass": h1_pass,
        "h3_pvalue": round(h3_pvalue, 6) if h3_pvalue is not None else None,
        "h3_pass": h3_pass,
        "h5_pvalue": round(h5_pvalue, 6) if h5_pvalue is not None else None,
        "h5_pass": h5_pass,
        "diagnostic_position_counts": dict(pos_counts),
        "diagnostic_label_counts": dict(lbl_counts),
        "diagnostic_semantic_counts": dict(sem_counts),
        "summaries": summaries,
    }
    (_RESULTS_DIR / f"{_DOMAIN['id'].lower()}-stats.json").write_text(json.dumps(results, indent=2))
    return results


# ─── CLI Dispatcher (must be called from per-domain toolkit) ──────────────

def cli_main(argv):
    if len(argv) < 2:
        print("Usage: <domain>/toolkit.py <cmd> <args>")
        print("Commands: prompt <rerun> <cell> | retry <rerun> <cell> <reason> |")
        print("          process-cell-file <rerun> <cell> <attempt> <raw_file> |")
        print("          summary <rerun> | stats | gen-all | perm <rerun>")
        sys.exit(1)

    cmd = argv[1]
    if cmd == "prompt":
        print(generate_prompt(int(argv[2]), int(argv[3])))
    elif cmd == "retry":
        print(generate_retry_prompt(int(argv[2]), int(argv[3]), argv[4]))
    elif cmd == "validate":
        status, obj = validate(argv[2])
        print(json.dumps({"status": status, "parsed": obj}))
    elif cmd == "process-cell-file":
        rerun = int(argv[2]); cell = int(argv[3]); attempt = int(argv[4])
        raw = Path(argv[5]).read_text().strip()
        m = re.search(r'\{[^{}]*"cell"[^{}]*"scores"[^{}]*\{[^{}]*\}[^{}]*\}', raw, re.DOTALL)
        raw_json = m.group(0) if m else raw
        status, obj = validate(raw_json)
        save_cell_result(rerun, cell, status, obj, raw_json, attempt)
        print(json.dumps({"status": status, "cell": cell, "rerun": rerun, "attempt": attempt}))
    elif cmd == "summary":
        print(json.dumps(save_rerun_summary(int(argv[2])), indent=2))
    elif cmd == "stats":
        print(json.dumps(compute_stats(), indent=2))
    elif cmd == "perm":
        r = int(argv[2])
        print(json.dumps({
            "rerun": r,
            "permutation": permutation_for_rerun(r),
            "A": option_for_label(r, "A"),
            "B": option_for_label(r, "B"),
            "C": option_for_label(r, "C"),
        }, indent=2))
    elif cmd == "gen-all":
        for rerun in range(1, 21):
            d = _RESULTS_DIR / "prompts" / f"rerun-{rerun:02d}"
            d.mkdir(parents=True, exist_ok=True)
            for c in range(1, 10):
                (d / f"cell-{c}.txt").write_text(generate_prompt(rerun, c))
        print(f"Wrote 180 prompts for {_DOMAIN['id']}")
    else:
        print(f"Unknown: {cmd}")
        sys.exit(1)
