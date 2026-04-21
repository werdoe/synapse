# Synapse — OpenClaw Skill
*Version: 1.0 | For: OpenClaw, Hermes, Claude Code*

---

## What This Skill Does

Synapse is a self-improving growth system for multi-agent fleets. It runs as an OpenClaw skill that agents use at startup and shutdown to:
- Write structured reflections
- Enforce session boundaries
- Feed the synthesis pipeline
- Build personal and shared guidance

This skill works in any OpenClaw-compatible system. It was designed on and for the Chandrian fleet (OpenClaw), but the patterns apply anywhere.

---

## Skill Triggers

| Trigger | Action |
|---------|--------|
| Agent starts session | Run Synapse startup sequence |
| Agent ends active session | Run Synapse shutdown sequence + write reflection |
| 4AM cron | Run synthesis pipeline |
| Orchestrator morning startup | Review proposals from yesterday |

---

## Quick Reference

### Session Startup Sequence

```
1. Read memory/guidance/{agent}.md       ← personal guidance
2. Read memory/guidance/shared.md        ← fleet guidance
3. Check session-open marker exists       ← prior session closed
4. Check proposals/.reviewed exists       ← prior proposals dispositioned
5. Read memory/synapse/contradiction-log.md  ← any open contradictions
6. Ready to work
```

### Session Shutdown Sequence

```
1. Write session-type declaration: memory/synapse/.session-type-{session-id}
   Value: "active" (real work) or "heartbeat-only" (no work)
2. Apply archive trigger test (GENERAL_LEARNINGS / NEEMCLAW_LEARNINGS)
3. Write reflection to memory/reflections/{agent}/{open-date}.md
4. Run shutdown gate (verifies reflection written, log entry updated)
```

### Reflection Format (by role)

**Technical:** Kilvin, Stercus, Bast
```
## Reflection — {HH:MM} — {N} — {task name}

### What did I do?
### What broke or surprised me?
### What would I do differently?
### Does this challenge any of my personal guidance?
### Flag for Kvothe:
```

**Strategic:** Kvothe, Haliax
```
## Reflection — {HH:MM} — {N} — {session summary}

### What actually moved forward today?
### What was harder than expected?
### What would I do differently?
### Does this challenge any of my personal guidance?
### What should the fleet know?
```

**Creative:** Cinder, Alenta, Dalcenti
```
## Reflection — {HH:MM} — {N} — {deliverable}

### What did I produce?
### What was harder to get right?
### What would I change on revision?
### Pattern I'm noticing in my own work:
```

**Assistant:** Auri, Lesley, Amina, Boots
```
## Reflection — {HH:MM} — {N} — {situation label}

### What situation did I handle that's worth reflecting on?
### What helped?
### What caused friction or confusion?
### Pattern I'm noticing:
```

---

## File Paths (relative to workspace root)

```
memory/
├── guidance/
│   ├── shared.md              ← fleet-wide guidance (GS-{nn})
│   └── {agent}.md            ← personal guidance (P-{agent}-{nn})
├── reflections/
│   └── {agent}/
│       └── YYYY-MM-DD.md      ← append model, one file per day
├── chronicles/
│   └── YYYY-MM-DD.md          ← tier-1 evidence (session logs)
└── synapse/
    ├── proposals/             ← synthesis candidates
    ├── chronicle-reflections/  ← synthesis narratives
    ├── contradiction-log.md
    ├── session-log.md
    ├── processed-registry.jsonl
    └── file-mtimes.json
```

---

## Synthesis Pipeline

**Schedule:** 4:00 AM local time, daily
**Runtime:** Isolated session, Sonnet-class model minimum

### Inputs
- All files in `memory/reflections/*/*.md` modified since last run (mtime tracked)
- Matching open-date chronicles for each reflection processed
- All `memory/guidance/{agent}.md` files
- `memory/guidance/shared.md`

### Processing Steps

1. **Catch-up** — list all reflection files, compare mtime against `file-mtimes.json`
2. **Chronicle coupling** — for each reflection file, read its open-date chronicle
3. **Dedupe** — check 4-tuple ID `{agent}::{open-date}::{N}::{HH:MM}` against `processed-registry.jsonl`
4. **Per-agent analysis** — classify evidence tier, compare against personal guidance
5. **Cross-agent pattern** — flag same pattern in 2+ agents as shared candidate
6. **Generate proposals** → `memory/synapse/proposals/{date}.md`
7. **Update contradiction log** — idempotent, key: agent + guidance key + evidence reference
8. **Write synthesis narrative** → `memory/synapse/chronicle-reflections/{date}.md`
9. **Commit** — append IDs to `processed-registry.jsonl` (only after steps 6–7 succeed)
10. **Update mtimes** — `file-mtimes.json`
11. **Write checkpoint** — `memory/synapse/checkpoint-{date}.md`

### Proposal Format

```markdown
## Candidate {N}
- agent: {name or "fleet"}
- type: personal | shared-candidate | contradiction-open | pattern-worth-examining
- proposed_key: P-{agent}-{nn} or GS-{nn}
- proposed_rule: {one-line rule}
- evidence_tier: {1|2|3|4}
- evidence: {reference}
- confidence: {0.70–1.00}
- promotion_path: requires_personal_first: yes (normal path)
- related_guidance: {existing key if any}
```

---

## Contradiction Log Format

```markdown
## Contradiction #{N} — {agent} — {date}
- Existing guidance: {P-key} — "{current rule}"
- Agent stated: "{from reflection}"
- Conflicting evidence: {source, tier, reference}
- Level 1 met: {yes — date opened}
- Level 2 met: {yes — date | no — N/3 confirmations}
- Status: OPEN | RESOLVED | SUPERSEDED | INVALID
- review_note: {orchestrator's decision}
- Resolution: {what changed}
- Resolved at: {date}
```

**Level 1 open:** 1 strong tier 1/2 conflict → open entry
**Level 2 act:** 3 confirmations OR 1 ≥0.90 confidence → update guidance

---

## Guidance File Format

**Personal (`memory/guidance/{agent}.md`):**
```markdown
# {Agent} — Personal Guidance
*Read before every reflection and before every significant task.*

## Active Guidance
| Key | Rule |
|---|---|
| P-{agent}-01 | {one-line behavioral rule} |

## Promotion History
| Date | Key | Promoted to | Reason |
|---|---|---|---|
```

**Shared (`memory/guidance/shared.md`):**
```markdown
# Shared Fleet Guidance
*Two valid promotion paths: (1) normal — same pattern confirmed by 2+ agents independently;
(2) exception — manual orchestrator, strong tier-1 chronicle evidence across multiple agents.*

## Active Guidance
| Key | Rule | Path | Confirmed By | Evidence | Date |
|---|---|---|---|---|---|
| GS-01 | {rule} | normal | P-kilvin-03, P-stercus-02 | G47 | YYYY-MM-DD |
```

---

## Session Lifecycle

**Bounded session:** startup gate → work → shutdown gate → session-log entry

### Startup Gate Checks
1. Chronicle exists for open-date
2. ACTIVE.md fresh (<8h)
3. `.reviewed` file exists for yesterday's proposals
4. Open contradictions have review_notes
5. No orphaned session markers (≥24h = hard fail)
6. NOTES.md not overdue

**On pass:** write `.session-open-{session_candidate}` marker

### Shutdown Gate Checks
1. Session-type declaration file exists
2. Reflection written (count = active closes in session-log)
3. Archive triggers applied (if fired → entry written)
4. Session-log entry written by gate (sole writer)
5. Kilvin spawns verified if any occurred that day

**On pass:** delete session-open marker

---

## Immutability Rule

Once a reflection entry's 4-tuple ID is in `processed-registry.jsonl`, that entry is immutable. To correct it, append a new entry with a new timestamp. The synthesis pipeline will skip the old ID (dedupe) and process the new one.

This applies to all agents. State it in your SOUL.md under the Synapse section.

---

## Naming Conventions

| Prefix | Scope | Home |
|--------|-------|------|
| `GS-{nn}` | Shared fleet guidance | `guidance/shared.md` |
| `P-{agent}-{nn}` | Personal guidance | `guidance/{agent}.md` |
| `G{nn}` | General archive | `GENERAL_LEARNINGS.md` |
| `N{nn}` | NeemClaw archive | `NEEMCLAW_LEARNINGS.md` |

---

## Evidence Hierarchy

| Tier | Source | Used for |
|------|--------|----------|
| 1 | Chronicle — logged events | Opening contradictions, exception-path GS promotions |
| 2 | Task artifacts — diffs, test outputs | Opening contradictions, promoting guidance |
| 3 | Reflection self-report | Pattern proposals, personal guidance |
| 4 | Synthesis inference | Pattern detection only |

Tier 3 alone cannot open a contradiction. Tier 1/2 can open and act.

---

## Setup Verification

Run this to verify your Synapse installation:

```bash
# Check all directories exist
for dir in memory/guidance memory/reflections memory/chronicles memory/synapse/proposals memory/synapse/chronicle-reflections; do
  [ -d "$dir" ] && echo "✓ $dir" || echo "✗ MISSING: $dir"
done

# Check runtime files
[ -f memory/synapse/session-log.md ] && echo "✓ session-log.md" || echo "✗ MISSING session-log.md"
[ -f memory/synapse/processed-registry.jsonl ] && echo "✓ processed-registry.jsonl" || echo "✗ MISSING processed-registry.jsonl"
[ -f memory/synapse/file-mtimes.json ] && echo "✓ file-mtimes.json" || echo "✗ MISSING file-mtimes.json"

# Check shared guidance
[ -f memory/guidance/shared.md ] && echo "✓ shared.md" || echo "✗ MISSING shared.md"

# Count agent guidance files
GUIDANCE_COUNT=$(ls memory/guidance/*.md 2>/dev/null | grep -v shared.md | wc -l | tr -d ' ')
echo "Agents with guidance files: $GUIDANCE_COUNT"
```

Expected output: all ✓ marks, at least 1 agent guidance file.

---

## Adapting for Hermes / Claude Code

Synapse is agent-format agnostic. To adapt for your system:

1. **Define agent roles** — map your agents to Technical/Strategic/Creative/Assistant
2. **Set workspace paths** — define where `memory/` lives relative to your agents
3. **Configure synthesis** — point the 4AM cron at your memory directory
4. **Set session IDs** — use `{open-date}-{HHMM}` format for consistent tracking
5. **Define your orchestrator** — who reviews proposals, manages contradictions, promotes shared guidance

The reflection formats work for any text-capable agent. The synthesis pipeline works with any file-based memory system. The enforcement tiers (1–4) are adjustable based on your fleet size.

---

## Files in This Skill

```
synapse-skill/
├── SKILL.md              ← This file
├── README.md             ← User-facing overview
├── SPEC.md               ← Full system specification
└── scripts/
    ├── synthesis.sh      ← 4AM synthesis cron
    ├── startup-gate.sh   ← Session startup verification
    ├── shutdown-gate.sh  ← Session shutdown verification
    └── template-reflections/
        ├── technical.md
        ├── strategic.md
        ├── creative.md
        └── assistant.md
```

---

*Synapse v1.0 — designed for the Chandrian fleet, built to be fleet-agnostic.*