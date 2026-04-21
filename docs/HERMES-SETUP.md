# Synapse + Hermes Setup Guide

Hermes is Anthropic's multi-agent CLI. Synapse integrates with it via the same file-based memory system.

---

## How Synapse + Hermes Works

Hermes already has a memory system. Synapse layers on top:
- **Reflection files** written by each Hermes agent at session end
- **Synthesis pipeline** reads Hermes agent output alongside other agents
- **Guidance files** influence which agent handles which task

Hermes sessions are typically longer-running. The wrapper approach works the same way — wrap the `hermes` binary.

---

## Quick Setup

### Step 1: Configure Hermes to use Synapse memory

In your `hermes.config.yaml`:

```yaml
memory:
  path: ./synapse-memory  # or a shared path

agents:
  # Each agent points to its reflection directory
  - name: architect
    memory:
      reflections: ./synapse-memory/reflections/architect
      guidance: ./synapse-memory/guidance
```

### Step 2: Point synthesis at your Hermes memory

In your synthesis cron, set `SYNAPSE_MEM` to wherever your Hermes memory lives:

```bash
SYNAPSE_MEM="/path/to/hermes/synapse-memory" ~/synapse/scripts/synthesis.sh
```

### Step 3: Add reflection prompts to your Hermes agent prompts

Each agent prompt should end with:

```
## Synapse Reflection (run at end of session)

Write a reflection to memory/reflections/{agent-name}/YYYY-MM-DD.md using
Technical, Strategic, Creative, or Assistant format based on your role.

Format: ## Reflection — {HH:MM} — {N} — {task name}

Append to the file. Create the file with header if it doesn't exist.
```

---

## Hermes-Specific Reflection Trigger

Hermes sessions are typically task-completion bounded. Trigger reflection when:
- A task is marked complete
- A subtask is done and handed off
- A session ends (keyboard interrupt, timeout)

---

## Next Steps

See [CLAUDE-CODE-SETUP.md](./CLAUDE-CODE-SETUP.md) for the wrapper script pattern — same approach works for Hermes.

For the full spec, see [SPEC.md](../SPEC.md).