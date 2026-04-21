# Synapse + Claude Code Setup

Two ways to integrate Synapse with Claude Code:

1. **Plugin (recommended)** — Claude Code lifecycle hooks, guidance auto-injected at session start
2. **Wrapper** — shell script wrapper for environments without plugin support

The plugin is the right way. The wrapper is for special cases.

---

## Option A: Claude Code Plugin (Recommended)

### How It Works

Claude Code has lifecycle hooks (same system Claude-Mem uses). Synapse uses them:

| Hook | What Happens |
|------|--------------|
| `SessionStart` | Guidance + past mistakes printed to stdout — Claude Code sees it |
| `UserPromptSubmit` | Your prompts logged to session track |
| `PostToolUse` | Tool results captured as tier-2 evidence |
| `Stop` | Reflection written automatically |
| `SessionEnd` | Synthesis pipeline triggered (throttled, every 4h+) |

The key insight from Claude-Mem: **`SessionStart` hook output goes to Claude Code's stdout** — so the guidance actually reaches the agent, not just a log file.

### Install

```bash
# From the plugin marketplace
/plugin marketplace add werdoe/synapse
/plugin install synapse

# Restart Claude Code
```

Or install via npm:

```bash
npx synapse install
```

### Configure

Create `~/.claude-mem/settings.json` equivalent for Synapse — either environment variables or a `.synapse-workspace` file:

```bash
# Environment variables
export SYNAPSE_ROOT="$HOME/synapse"
export SYNAPSE_AGENT_NAME="claude-code"
export SYNAPSE_MEM="$HOME/.synapse-memory"

# Optional: show guidance at session start (default: true)
export SYNAPSE_VERBOSE=true
```

Or create `.synapse-workspace` in your project:

```bash
SYNAPSE_ROOT="$HOME/synapse"
SYNAPSE_AGENT_NAME="claude-code"
SYNAPSE_MEM="./.synapse-memory"
```

### What You See at Session Start

```
🧠 Synapse — your active guidance:

## Your Synapse Personal Guidance
- [P-claude-code-01] verify before building — check OpenClaw docs first
- [P-claude-code-02] always run preflight before Kilvin spawn

## Synapse Fleet Guidance (shared patterns)
- [GS-01] verify before Kilvin spawn

Past mistakes to avoid:
  • gateway startup times out on MacBook
  • token mismatch after restart
```

This appears every time Claude Code starts. Your patterns are in front of you before you begin work.

### Memory Structure Created

```
~/.synapse-memory/
├── guidance/
│   ├── claude-code.md       ← auto-populated by synthesis
│   └── shared.md            ← fleet guidance (multi-agent)
├── reflections/
│   └── claude-code/
│       └── YYYY-MM-DD.md    ← one file per day, auto-written
├── chronicles/
│   └── YYYY-MM-DD.md
└── synapse/
    ├── proposals/            ← synthesis candidates
    ├── observations/         ← tier-2 tool use evidence
    ├── session-log.md
    └── contradiction-log.md
```

---

## Option B: Wrapper Script (Fallback)

For environments where the plugin isn't available. See `scripts/claude-code-wrapper.sh` in the Synapse repo.

**Limitation:** The wrapper can't inject guidance into Claude Code's context — it only prints to terminal. Claude Code won't read it automatically. Use the plugin instead.

---

## Auto-Promotion

High-confidence patterns auto-append to your guidance file:

- **Tier 1/2 evidence** (chronicle events, verified task artifacts) → auto-promote
- **Tier 3** (self-reports) → proposal only, manual review

The synthesis pipeline runs every 4+ hours (throttled). Your guidance file grows automatically from session reflections.

---

## Limitations (Honest)

| Feature | Plugin | Notes |
|---------|--------|-------|
| Guidance in context | ✅ Yes | Via SessionStart hook stdout |
| Reflection auto-written | ✅ Yes | Via Stop hook |
| Multi-agent patterns | ⚠️ Limited | Only works if multiple agents use the same SYNAPSE_MEM |
| Orchestrator review | ❌ Manual | You review proposals (same as wrapper) |
| Contradiction management | ⚠️ Logged | Notification fires but resolution is manual |

The orchestrator layer (promotion review, contradiction resolution, shared guidance) is still manual — the plugin handles the reflection loop and synthesis, not the governance.

---

## Uninstall

```bash
/plugin uninstall synapse
rm -rf ~/.synapse-memory  # optional — your reflections
```

---

*For the full system spec, see [SPEC.md](../SPEC.md).*