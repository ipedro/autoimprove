---
name: decisions
description: "Use when the user wants to browse, list, or review archived design decisions. Triggers on: 'show decisions', 'list decisions', 'review past decisions', 'what did we decide', 'decision archive'. Optionally filter by keyword slug. Can show summary or full content of specific decisions."
argument-hint: "[<keyword>] [--full]"
allowed-tools: [Read, Bash, Glob]
---

<SKILL-GUARD>
You are NOW executing the decisions skill. Do NOT invoke this skill again via the Skill tool — execute the steps below directly.
</SKILL-GUARD>

Browse archived decisions from `decisions/`. Read-only — makes no changes.

Parse user input:
- `<keyword>` — filter filenames by substring (case-insensitive, matched against slug)
- `--full` — print full file content instead of summary line per decision

---

# 1. List Decision Files

```bash
ls decisions/ 2>/dev/null | sort -r
```

If the directory is missing or empty, print:
```
No decisions archived yet. Run /idea-matrix then /idea-archive to create one.
```
and stop.

---

# 2. Apply Keyword Filter

Keep only filenames containing `<keyword>` (case-insensitive). If no keyword, keep all.

If result is empty, print:
```
No decisions match "<keyword>". Try a broader term or omit the keyword to list all.
```
and stop.

---

# 3. Display Results

For each matched file (newest-first — filenames are YYYY-MM-DD-prefixed):

**Summary mode (default):** Read YAML frontmatter and print:
```
<YYYY-MM-DD>  <slug>  |  Winner: <winner>  |  Verdict: <verdict_type>  (score: <composite_score>/5)
```
`<slug>` = filename minus `YYYY-MM-DD-` prefix and `.md` suffix.

If frontmatter is missing or malformed: `<YYYY-MM-DD>  <slug>  |  [unreadable]`

**Full mode (`--full`):** Print complete file content for each match, separated by `---`.

---

# 4. Summary Line

```
<N> decision(s) found — keyword: <keyword> | (no filter)
```

If archive has >50 files, suggest using a keyword to narrow results.
Files not matching `YYYY-MM-DD-*.md` pattern are listed separately under `Unrecognized files:`.
