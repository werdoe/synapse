# Synapse + Claude Code Setup Guide

This guide walks you through integrating Synapse with Claude Code. Read the limitations section first — Synapse was designed for multi-agent fleets and some features require adaptation for single-agent use.

---

## What This Enables

When you run Claude Code through the Synapse wrapper:
1. **Reflection loop** — every session produces a structured reflection that feeds synthesis
2. **mtime-based catch-up** — synthesis picks up late reflections on the next run
3. **Guidance accumulation** — your reflections build a personal guidance file over time

What it **can't** do without an orchestrator:
- Automatic promotion of patterns to shared guidance
- Cross-agent pattern detection
- Contradiction management

---

## Prerequisites

- [x] Synapse installed (`git clone https://github.com/werdoe/synapse.git`)
- [x] Claude Code installed and authenticated
- [x] jq installed (`brew install jq`)
- [x] bash 4+ (macOS default is fine)

---

## Limitations You Should Know

### 1. No Orchestrator (you are Kvothe)

Synapse assumes a separate orchestrator agent reviews 4AM synthesis proposals, manages the contradiction log, and promotes patterns to shared guidance. With Claude Code alone, **you fill that role**.

**What you do:**
- After synthesis runs, read `memory/synapse/proposals/YYYY-MM-DD.md`
- Edit `memory/guidance/claude-code.md` to add/update your personal guidance
- Edit `memory/guidance/shared.md` if you want fleet-level guidance (only makes sense if multiple agents contribute)

**Practical mode:** Set `SYNAPSE_REVIEW_MODE=manual` in your config. Synthesis will write proposals but not attempt any automatic promotion. You review and apply.

### 2. No Session Lifecycle Hooks

Claude Code has no native "session ended" event. The wrapper runs the shutdown gate after every call, but this only works if every Claude Code invocation goes through the wrapper.

**What you do:**
- Use the alias (`cc`) for every Claude Code call — no direct `claude --print` calls
- If you forget and run direct, the reflection won't be written (no recovery within the session)
- Synthesis runs at 4AM picks up any reflections that exist by then

**Better pattern:** Run synthesis manually after any significant session:
```bash
./scripts/synthesis.sh --dry-run  # preview what it would do
./scripts/synthesis.sh            # actually run
```

### 3. No Multi-Agent Pattern Detection

Synapse's power is cross-agent pattern matching — the same mistake caught independently by Kilvin, Stercus, and Bast surfaces as a shared candidate. With one agent (Claude Code), synthesis can only find patterns within your own reflection history.

**What you get:** Personal growth loop — not fleet-wide intelligence.

**What you can do:** Point multiple Claude Code sessions (different projects, different agent names) at the same shared memory path. Different `SYNAPSE_AGENT_NAME` values write to different reflection directories. Synthesis reads all of them and can detect cross-project patterns.

---

## Setup

### Step 1: Config file

In your project root or home directory:

```bash
cat > .synapse-workspace << 'EOF'
SYNAPSE_ROOT="$HOME/synapse"
SYNAPSE_AGENT_NAME="claude-code"
SYNAPSE_MEM="$HOME/.synapse-memory"
SYNAPSE_REVIEW_MODE="manual"
EOF
```

### Step 2: Alias

```bash
echo 'alias cc="$HOME/synapse/scripts/claude-code-wrapper.sh"' >> ~/.zshrc
source ~/.zshrc
```

### Step 3: Run via Synapse

```bash
cc --print --permission-mode bypassPermissions
cc --print --project /path/to/project --permission-mode bypassPermissions
```

---

## The Manual Orchestrator Workflow

After each session (or batch of sessions), you review proposals:

```bash
# Run synthesis
~/synapse/scripts/synthesis.sh

# Read what it generated
cat ~/.synapse-memory/synapse/proposals/$(date +%Y-%m-%d).md

# Edit your personal guidance
nano ~/.synapse-memory/guidance/claude-code.md

# Or promote to shared if multiple agents use this memory
nano ~/.synapse-memory/guidance/shared.md
```

**Proposal format:**
```markdown
## Candidate {N}
- agent: claude-code
- type: personal | shared-candidate
- proposed_key: P-claude-code-01
- proposed_rule: {one-line rule}
- evidence_tier: 3
- evidence: reflection YYYY-MM-DD HHMM (self-report)
- confidence: 0.72
- promotion_path: requires_personal_first: yes
```

To promote: copy `proposed_rule` into your guidance file with the `P-claude-code-{nn}` key.

---

## Multiple Claude Code Agents (Better Pattern)

If you work across multiple projects, use separate agent names:

```bash
# Project A
SYNAPSE_AGENT_NAME="cc-project-a" SYNAPSE_MEM="/shared/synapse-memory" cc --print ...

# Project B
SYNAPSE_AGENT_NAME="cc-project-b" SYNAPSE_MEM="/shared/synapse-memory" cc --print ...
```

Synthesis reads all reflection directories and catches patterns across projects. This gets you closer to the actual Synapse value — cross-agent pattern detection with a single-user setup.

---

## Reflection Format (Technical)

The wrapper writes Technical format reflections:

```markdown
## Reflection — {HH:MM} — {N} — {task}

### What did I do?
### What broke or surprised me?
### What would I do differently?
### Does this challenge any of my personal guidance?
### Flag for:
```

Prompts are inline after each session. Set env vars to skip prompts:
```bash
SYNAPSE_SUMMARY="built auth system" SYNAPSE_BROKE="token refresh edge case" cc --print
```

---

## Running Without Synapse

```bash
# Direct call (no wrapper)
claude --print --permission-mode bypassPermissions

# Or with wrapper disabled
SYNAPSE_MEM="" ./synapse/scripts/claude-code-wrapper.sh --print
```

---

## Honest Assessment

| Feature | Synapse on OpenClaw | Synapse on Claude Code |
|---------|---------------------|------------------------|
| Reflection loop | ✅ Native | ✅ Wrapper (manual hooks) |
| 4AM synthesis | ✅ Native cron | ✅ System cron (same) |
| Orchestrator review | ✅ Kvothe agent | ❌ You (manual) |
| Cross-agent patterns | ✅ 11-agent fleet | ⚠️ Multiple CC sessions only |
| Contradiction management | ✅ Auto | ❌ Manual |
| Shared guidance | ✅ Auto-promotion | ⚠️ You edit files manually |
| Session gates | ✅ Native | ⚠️ Shell wrapper |

**The wrapper gives you the reflection loop and synthesis.** The orchestrator layer (promotion, contradiction handling, shared guidance) is manual with Claude Code. That's the honest tradeoff.

For single-agent use, Synapse still helps — it just requires you to do the synthesis review work that Kvothe automates on OpenClaw.

---

*See [SPEC.md](../SPEC.md) for the full system specification.*