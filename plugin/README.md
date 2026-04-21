# Synapse — Claude Code Plugin

A Claude Code plugin that gives Claude Code the Synapse growth system: guidance injection at session start, automatic reflection on session end, and synthesis pipeline integration.

---

## How It Works

Claude-Mem showed the way: Claude Code has **lifecycle hooks** that fire at specific points in a session. Synapse uses them the same way:

```
SessionStart → inject-guidance.js → prints your patterns before work begins
UserPromptSubmit → session-track.js → logs what you're working on
PostToolUse → observe.js → captures what actually happened (tier-2 evidence)
Stop → write-reflection.js → writes your reflection automatically
SessionEnd → synthesis-trigger.js → kicks off the synthesis pipeline
```

The critical piece from Claude-Mem: **the SessionStart hook prints guidance to stdout**, which Claude Code sees at the start of every session. This is how Synapse guidance gets into the agent's context — not a config file, not a system prompt, just stdout that Claude reads.

---

## Installation

### Option A: From Plugin Marketplace

```bash
/plugin marketplace add werdoe/synapse
/plugin install synapse
```

### Option B: Manual

```bash
git clone https://github.com/werdoe/synapse.git ~/synapse-plugin-temp
# Then move to Claude plugins directory
# (plugin marketplace handles this automatically)
```

---

## Configuration

Set environment variables before starting Claude Code:

```bash
# Required
export SYNAPSE_ROOT="$HOME/synapse"           # where Synapse is installed
export SYNAPSE_AGENT_NAME="claude-code"      # your agent name

# Optional — point to a different memory location
export SYNAPSE_MEM="$HOME/.synapse-memory"
```

Or create a `.synapse-workspace` file in your project:

```bash
SYNAPSE_ROOT="$HOME/synapse"
SYNAPSE_AGENT_NAME="claude-code"
SYNAPSE_MEM="./.synapse-memory"
```

---

## What You Get

### At Session Start (SessionStart hook)

Claude Code sees something like:

```
🧠 Synapse — your active guidance:

## Your Synapse Personal Guidance
- [P-claude-code-01] verify before building — check OpenClaw docs first
- [P-claude-code-02] always run preflight before Kilvin spawn

## Synapse Fleet Guidance (shared patterns)
- [GS-01] verify before Kilvin spawn — read the actual source

Past mistakes to avoid:
  • gateway startup times out on MacBook
  • token mismatch after restart
```

### After Session Ends (Stop hook)

Reflection is written automatically. No prompts, no manual steps.

### Nightly (synthesis pipeline)

Same as the standard Synapse setup — 4AM synthesis picks up all reflections, generates proposals, auto-promotes high-confidence entries to your guidance file.

---

## Files Created

```
~/.synapse-memory/
├── guidance/
│   ├── claude-code.md      ← your personal guidance (auto-populated)
│   └── shared.md           ← fleet guidance (if multi-agent)
├── reflections/
│   └── claude-code/
│       ├── 2026-04-21.md
│       └── 2026-04-22.md
├── chronicles/
│   └── 2026-04-22.md
└── synapse/
    ├── proposals/          ← synthesis candidates
    ├── observations/       ← tier-2 tool use evidence
    ├── session-log.md
    └── contradiction-log.md
```

---

## Hook Behavior

| Hook | Script | Purpose | Blocking? |
|------|--------|---------|-----------|
| Setup | init.js | Initialize memory + guidance files | No |
| SessionStart | inject-guidance.js | Print guidance + write inject file | No |
| UserPromptSubmit | session-track.js | Log user prompts | No |
| PostToolUse | observe.js | Capture tool results (tier-2 evidence) | No |
| Stop | write-reflection.js | Write automatic reflection | No |
| SessionEnd | synthesis-trigger.js | Kick off synthesis (throttled) | No |

All hooks exit 0 — errors are non-blocking. Claude Code never pauses waiting for Synapse.

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `SYNAPSE_ROOT` | `$HOME/synapse` | Synapse installation directory |
| `SYNAPSE_MEM` | `$SYNAPSE_ROOT/memory` | Memory directory |
| `SYNAPSE_AGENT_NAME` | `claude-code` | Your agent name in reflections |
| `SYNAPSE_VERBOSE` | `true` | Show guidance at session start |
| `SYNAPSE_INTERACTIVE` | `0` | Prompt for reflection input after Stop (not needed with auto-reflection) |

---

## Uninstall

```bash
/plugin uninstall synapse
# Then remove memory if desired
rm -rf ~/.synapse-memory
```

---

## Synapse System (Full)

This plugin handles the Claude Code integration. For the full Synapse system (synthesis pipeline, contradiction management, promotion ladder), see [SPEC.md](../SPEC.md).

The plugin replaces the wrapper script approach — it gives you the same capabilities but native to Claude Code's lifecycle rather than a shell wrapper.

---

*Synapse v1.0 — built on the Claude-Mem hook architecture for Claude Code.*