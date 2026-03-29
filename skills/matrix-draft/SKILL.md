---
name: matrix-draft
description: "Use when the user says 'draft idea matrix', 'help me set up idea-matrix', 'prepare for idea-matrix', 'matrix prep', or wants help formulating a crisp problem statement and well-differentiated options before running idea-matrix. Asks clarifying questions, sharpens the problem statement to one sentence, surfaces 3-5 truly distinct options, and outputs a ready-to-paste block for /idea-matrix."
argument-hint: "<rough problem description or topic>"
allowed-tools: []
---

<SKILL-GUARD>
You are NOW executing the matrix-draft skill. Do NOT invoke this skill again.
</SKILL-GUARD>

Pre-process a fuzzy problem into a crisp `/idea-matrix` input. No tools — all reasoning from conversation context.

---

# 1. Sharpen the Problem Statement

Ask ONE clarifying question if the problem is vague:
- Symptom ("things are slow") → "What decision does fixing this require?"
- Goal ("make it faster") → "What are you choosing between to get there?"
- Solution ("use caching") → "What problem does this solve, and are there alternatives?"

Write the problem as one sentence: **"How should we [verb] [object] given [constraint]?"**

Confirm: "Is this the decision you're trying to make?"

---

# 2. Surface 3–5 Distinct Options

**Differentiation test:** Each option must take a meaningfully different approach — not just vary a parameter. If two options differ only in degree ("same thing but faster/simpler"), merge them or replace one.

If fewer than 3 distinct options exist, ask: "What would you do if your first choice was impossible?" This reliably surfaces a third path.

```
A: <short label> — <what it does and what it bets on>
B: <short label> — <what it does and what it bets on>
C: <short label> — <what it does and what it bets on>
```

---

# 3. Quick Feasibility Check

For each option, flag obvious blockers before spawning 9 haiku agents:
- Technically impossible given the current stack? → `[BLOCKED: reason]`
- Depends on something that doesn't exist yet? → `[BLOCKED: reason]`

Replace or remove blocked options. If all pass: "All options are feasible — ready to run the matrix."

---

# 4. Output Ready-to-Paste Block

```
Problem: <one-sentence problem statement>

Options:
A: <label> — <description>
B: <label> — <description>
C: <label> — <description>
```

Then: "Run `/idea-matrix` with the block above, or adjust any option before proceeding."

---

# Notes

- **Stay under 5 exchanges.** If clarification takes more than 2 back-and-forths, tell the user to narrow scope first.
- **Don't pre-score options.** Evaluation is idea-matrix's job — this skill only frames the question well.
