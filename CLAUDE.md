# Synapse — Claude Code Context

You are working in the Synapse repository. This is a self-improving growth system for multi-agent AI fleets.

## Key Files

| File | Purpose |
|------|---------|
| `SPEC.md` | Full system specification — canonical reference |
| `plugin/hooks/hooks.json` | Claude Code lifecycle hook definitions |
| `plugin/scripts/` | Hook scripts (init, inject-guidance, observe, etc.) |
| `scripts/synthesis.sh` | 4AM synthesis pipeline |
| `scripts/startup-gate.sh` | Session startup verification |
| `scripts/shutdown-gate.sh` | Session shutdown verification |
| `docs/CLAUDE-CODE-SETUP.md` | Integration guide for Claude Code |

## Architecture

The plugin system mirrors Claude-Mem's hook architecture:

- **Setup** → initializes memory structure
- **SessionStart** → inject-guidance.js prints guidance to stdout (goes into Claude's context)
- **UserPromptSubmit** → logs user prompts
- **PostToolUse** → captures tool results as tier-2 evidence
- **Stop** → writes automatic reflection
- **SessionEnd** → triggers synthesis pipeline (throttled)

## Building

To update the plugin scripts after editing:

```bash
# Scripts are standalone Node.js — no build step needed
node plugin/scripts/inject-guidance.js  # test
```

## Testing Hooks Locally

```bash
# Simulate SessionStart hook
SYNAPSE_ROOT="$PWD" SYNAPSE_AGENT_NAME="test" node plugin/scripts/inject-guidance.js

# Simulate Stop hook
SYNAPSE_ROOT="$PWD" SYNAPSE_AGENT_NAME="test" node plugin/scripts/write-reflection.js
```

## Key Design Decisions

1. **All hooks exit 0** — errors are non-blocking, Claude Code never waits
2. **Throttling on synthesis** — max once per 4 hours to avoid spam
3. **Observation collection** — PostToolUse captures tier-2 evidence for contradictions
4. **Auto-promotion** — tier 1/2 candidates go straight to guidance without review
5. **Inject file** — `.synapse-inject.md` written on SessionStart, read by Claude Code

## Synapse Growth Loop

```
SessionStart: guidance injected → agent sees patterns
    ↓
Work happens + PostToolUse captures observations
    ↓
Stop: reflection auto-written
    ↓
SessionEnd: synthesis triggered (throttled)
    ↓
4AM synthesis: proposals generated
    ↓
High-confidence entries auto-promoted to guidance
    ↓
Next SessionStart: updated guidance injected
```

The loop closes itself. You don't need to manage it once it's running.