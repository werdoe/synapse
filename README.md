# Synapse — Unified Growth System for AI Agent Fleets

> Self-improving framework for multi-agent teams. Learn from every session. Promote patterns from personal insight to shared fleet knowledge.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Status: Production](https://img.shields.io/badge/Status-Production-green.svg)](#status)

**Docs:** [SPEC.md](SPEC.md) · [README](README.md) · [SKILL.md](SKILL.md)

---

## What is Synapse?

Synapse is a self-improving growth system for AI agent fleets. It runs on a simple loop:

```
Session → Reflection → Synthesis → Guidance → Better Sessions
```

Every session produces structured reflections. A nightly synthesis run catches patterns across agents. The orchestrator reviews and promotes patterns — personal guidance becomes shared fleet knowledge.

The result: mistakes stop repeating. Insights compound. Every agent gets smarter without every agent having to make every mistake.

---

## Status

Synapse is **production-ready** and actively running on the [Chandrian fleet](https://github.com/werdoe/neemclaw-reloaded) (11 agents, OpenClaw).

The core system is framework-agnostic. See [Adapting for Hermes / Claude Code](#adapting-for-hermes-claude-code) below.

---

## Key Features

- **Four evidence tiers** — synthesis prioritizes chronicle events and task artifacts over self-reports
- **Promotion ladder** — personal → shared only with sufficient independent confirmation
- **Formal contradiction handling** — evidence-based, two-level open/act standard
- **Session lifecycle** — bounded sessions with startup/shutdown gates that prevent orphaned state
- **Immutability** — once processed, reflections are locked; corrections are new entries
- **mtime-based catch-up** — synthesis never misses late-arriving reflections across midnight

---

## Quick Start

### 1. Clone

```bash
git clone https://github.com/werdoe/synapse.git
cd synapse
```

### 2. Set up the memory directory structure

```bash
mkdir -p memory/{guidance,reflections,chronicles,synapse/proposals,synapse/chronicle-reflections}
touch memory/synapse/{session-log.md,processed-registry.jsonl,file-mtimes.json}
```

### 3. Create your first agent's guidance file

```bash
cat > memory/guidance/shared.md << 'EOF'
# Shared Fleet Guidance
*Two valid promotion paths: (1) normal — 2+ agents independently confirmed;
(2) exception — manual orchestrator with tier-1 chronicle evidence.*

## Active Guidance
| Key | Rule | Path | Confirmed By | Evidence | Date |
|---|---|---|---|---|---|
EOF
```

### 4. Configure the synthesis cron

```bash
# Add to crontab (4AM your timezone)
crontab -e
# 0 4 * * * /path/to/synapse/scripts/synthesis.sh >> /path/to/logs/synthesis.log 2>&1
```

### 5. Run startup gate

```bash
./scripts/startup-gate.sh
```

---

## File Structure

```
synapse/
├── README.md                      ← Overview (you are here)
├── SPEC.md                       ← Full system specification (canonical reference)
├── SKILL.md                      ← OpenClaw skill implementation
├── LICENSE                       ← MIT
├── scripts/
│   ├── synthesis.sh              ← Nightly synthesis pipeline
│   ├── startup-gate.sh           ← Session startup verification
│   ├── shutdown-gate.sh          ← Session shutdown verification
│   └── template-reflections/
│       ├── technical.md
│       ├── strategic.md
│       ├── creative.md
│       └── assistant.md
```

---

## Reflection Formats

Synapse has four format types. Agents write in their role's format; synthesis handles pattern-matching.

### Technical (Builders, QA, Reviewers)
```markdown
## Reflection — {HH:MM} — {N} — {task name}

### What did I do?
### What broke or surprised me?
### What would I do differently?
### Does this challenge any of my personal guidance?
### Flag for Kvothe:
```

### Strategic (Orchestrators, Product)
```markdown
## Reflection — {HH:MM} — {N} — {session summary}

### What actually moved forward today?
### What was harder than expected?
### What would I do differently?
### Does this challenge any of my personal guidance?
### What should the fleet know?
```

### Creative (Writers, Marketing, Social)
```markdown
## Reflection — {HH:MM} — {N} — {deliverable}

### What did I produce?
### What was harder to get right?
### What would I change on revision?
### Pattern I'm noticing in my own work:
```

### Assistant (Personal Assistants, Support)
```markdown
## Reflection — {HH:MM} — {N} — {situation label}

### What situation did I handle that's worth reflecting on?
### What helped?
### What caused friction or confusion?
### Pattern I'm noticing:
```

---

## The Evidence Tiers

| Tier | Source | Used For |
|------|--------|----------|
| 1 | Chronicle — logged events with timestamps | Opening contradictions, exception-path promotions |
| 2 | Task artifacts — git diffs, test outputs, build logs | Opening contradictions, promoting guidance |
| 3 | Reflection self-report | Pattern proposals, personal guidance only |
| 4 | Synthesis inference | Pattern detection only |

**Tier 1/2 required to open a contradiction.** Tier 3 alone cannot bypass evidence requirements.

---

## The Promotion Ladder

```
STEP 1 — Reflection
  Agent writes structured reflection at end of session

STEP 2 — Proposal Candidate
  4AM synthesis generates when: same pattern in 3+ reflections
  OR tier 1/2 evidence confirms a reflection's claim

STEP 3 — Personal Guidance
  Orchestrator promotes when: confidence ≥ 0.85 AND
  (tier 1/2 present OR 3+ independent reflections)

STEP 4 — Shared Guidance
  Promoted when: same pattern independently appears in
  2+ different agents' personal guidance files

EXCEPTION: Direct-to-shared from strong tier-1 chronicle evidence
(multi-agent failure in one event) — manual orchestrator only,
never generated by synthesis
```

---

## Session Lifecycle

Every session is a bounded unit. The startup gate verifies prior session closed cleanly. The shutdown gate verifies reflections were written and updates the session log.

```
startup-gate.sh → session-open marker written → WORK → shutdown-gate.sh → session-log entry
```

**Cross-midnight rule:** Sessions belong to their open date — the date the session started. All checks use the locked open date, not the wall-clock close date.

---

## Adapting for Hermes / Claude Code

Synapse is agent-format agnostic. To adapt:

1. **Define agent roles** — map your agents to Technical/Strategic/Creative/Assistant
2. **Set workspace paths** — define where `memory/` lives in your environment
3. **Configure synthesis** — point the 4AM cron at your memory directory
4. **Set session IDs** — use `{open-date}-{HHMM}` format for consistent tracking
5. **Define your orchestrator** — who reviews proposals, manages contradictions, promotes shared guidance

The reflection formats work for any text-capable agent. The synthesis pipeline works with any file-based memory system.

---

## Integration with OpenClaw

Place `SKILL.md` in your OpenClaw skills directory. Synapse integrates natively with OpenClaw's session lifecycle (startup/shutdown sequences), cron scheduler, and sub-agent spawning.

See `SKILL.md` for the full skill implementation.

---

## Specification

The canonical system specification is in `SPEC.md`. It covers:
- All 14 parts: inventory, diagnosis, requirements, design, evidence tiers, promotion ladder, synthesis pipeline, contradiction handling, session lifecycle, per-agent protocols, migration plan, failure modes, acceptance criteria
- Full file structure with runtime transient artifacts
- Formal definition of session lifecycle (cross-midnight, open-date locking)
- Startup and shutdown gate logic (CHECK 1–7)
- Synthesis commit order and failure modes

Reference `SPEC.md` for any ambiguity. The README is the overview; the spec is the source of truth.

---

## License

MIT — see [LICENSE](LICENSE)