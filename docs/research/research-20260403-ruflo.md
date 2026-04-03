# Scout Report: ruflo (claude-flow v3.5) — Fault Tolerance + Specialized Agents

**Date:** 2026-04-03  
**Issue:** #97  
**Scope:** ruvnet/ruflo — 5,900+ commits, 60+ agents, TypeScript CLI

---

## 1. Fault-Tolerant Consensus

### What ruflo does

Ruflo's `hive-mind` command implements **Queen-led Byzantine fault-tolerant consensus** with four selectable consensus algorithms:

| Algorithm | Fault model | Tolerance |
|-----------|-------------|-----------|
| `byzantine` | BFT (arbitrary failures) | f < n/3 faulty |
| `raft` | Crash failures (default) | f < n/2 |
| `gossip` | Eventual consistency | partition-tolerant |
| `crdt` | Conflict-free merge | split-brain safe |

The `SwarmCoordinator.reachConsensus()` method collects votes from named agents and applies a simple majority (>50%) gate — the BFT variants are higher-level policies around this base. Agent health is tracked per-agent via `AgentMetrics { health, successRate, tasksFailed }`. When an agent's task returns `status: 'failed'`, the coordinator records the failure, updates `successRate`, and the task simply goes unassigned (no retry or re-dispatch built in at this level — it surfaces upstream).

**Key finding:** The actual BFT is **not wired into the E→A→J style serial chain**. It applies to swarm-voting scenarios (multiple agents vote on a decision). The serial chain (step A must complete before step B) has no native fault recovery in ruflo either — failures surface as errors to the orchestrator.

### What we could adopt

**Actionable:** Add a **re-dispatch policy** in the AR orchestrator for the malformed-JSON fallback paths that already exist. Currently, when enthusiast/adversary/judge returns invalid JSON, we re-prompt once then fall back to empty output. We could instead re-dispatch to a fresh agent instance before falling back — this mirrors ruflo's "retry with a different worker" pattern without needing full BFT.

**Not applicable:** The `raft`/`byzantine` consensus is for *voting across parallel agents on a shared decision*. Our E→A→J is a serial debate — majority voting doesn't map to it. Each agent has a distinct asymmetric role; we can't swap them or vote across them.

---

## 2. Specialized Agents Per Domain

### What ruflo does

Ruflo auto-selects a **task-complexity-based swarm template** with specialized roles per domain:

| Code N | Domain | Agents spawned |
|--------|--------|----------------|
| 7 | Performance | coordinator, perf-engineer, coder |
| 9 | Security | coordinator, security-architect, auditor |
| 11 | Memory | coordinator, memory-specialist, perf-engineer |

The agent *type* controls which tasks it `canExecute()`. A `security-architect` agent accepts `security` typed tasks; a `tester` accepts `test` typed tasks. This is **routing by task type**, not prompt specialization — each type has a YAML capability list (`capabilities: [code-review, quality-analysis]`).

**Key finding:** Ruflo's specialization is **agent-routing** (which agent handles which task category) not **prompt tuning** (different system prompts per language/domain). The actual LLM instructions are sparse in the YAML configs. The "specialization" is structural: the right agent type is selected for a task type.

### What we could adopt

**Actionable:** Our `enthusiast-spec` / `adversary-spec` / `judge-spec` agent variants already implement this pattern for spec vs code targets. Extend this to a third track: a **security-focused track** where all three agents receive a security-biased system prompt (OWASP top-10 lens, privilege escalation, injection). Triggered when the diff or target contains `auth`, `token`, `crypto`, `password`, or `exec`.

**Not applicable:** Ruflo's per-language specialization (mobile-dev, ml-developer, etc.) requires task routing infrastructure. Our AR skill operates on arbitrary code targets — pre-routing by language would need target-type detection we don't have and would add complexity for marginal gain.

---

## Recommendations

1. **Re-dispatch on agent failure (fault tolerance):** Before the existing malformed-JSON fallback (which currently uses empty output), attempt one re-dispatch to a fresh agent call. Cost: one extra agent call per failure event, which is rare. Prevents silent degradation when a single agent times out or halts mid-response.

2. **Security-focused AR track:** Add `enthusiast-security.md` / `adversary-security.md` / `judge-security.md` agents with security-biased prompts. The SKILL.md target-type detection already has a pattern to follow (the `spec` track). This directly improves AR quality for the most high-stakes finding category.

---

*Report based on: ruflo v3.5 source at ruvnet/ruflo (main branch, 2026-04-03). SwarmCoordinator.ts, Agent.ts, CLAUDE.md, agents/*.yaml inspected directly via GitHub API.*
