# Synapse + Claude Code Setup Guide

This guide walks you through integrating Synapse with Claude Code (claude --print or claude-code CLI).

---

## What This Enables

When you run Claude Code through the Synapse wrapper:
1. **Startup gate** verifies prior session closed cleanly
2. **Session lifecycle** is tracked with proper open-date locking
3. **Reflection** is written after every session (prompted interactively)
4. **Synthesis** picks up your Claude Code reflections alongside other agents
5. **Guidance** from the fleet influences your session

Without the wrapper, Claude Code still works — it's just not integrated into the growth system.

---

## Prerequisites

- [x] Synapse installed (`git clone https://github.com/werdoe/synapse.git`)
- [x] Claude Code installed and authenticated (`claude --auth` or API key set)
- [x] jq installed (`brew install jq`)
- [x] bash 4+ (macOS default is fine, Linux: `brew install bash`)

---

## Option A: Per-Project Setup (Recommended)

### Step 1: Create a `.synapse-workspace` config file

In your project root:

```bash
# Create the config
cat > .synapse-workspace << 'EOF'
SYNAPSE_ROOT="$HOME/synapse"
SYNAPSE_AGENT_NAME="claude-code"
SYNAPSE_MEM="./.synapse-memory"
EOF

# Add to .gitignore
echo ".synapse-memory/" >> .gitignore
echo ".synapse-workspace" >> .gitignore
```

**Config values:**
- `SYNAPSE_ROOT` — path to where you cloned Synapse
- `SYNAPSE_AGENT_NAME` — name used in reflection files (change if multiple Claude Code agents)
- `SYNAPSE_MEM` — path to this project's Synapse memory directory (can be `.synapse-memory/` locally or a shared path)

### Step 2: Make the wrapper executable

```bash
chmod +x ~/synapse/scripts/claude-code-wrapper.sh
```

### Step 3: Create an alias (optional but recommended)

Add to your `~/.zshrc` or `~/.bashrc`:

```bash
alias cc="~/synapse/scripts/claude-code-wrapper.sh"
```

Then reload:

```bash
source ~/.zshrc
```

### Step 4: Run Claude Code via Synapse

```bash
# Normal session
cc --print --permission-mode bypassPermissions

# With a project directory
cc --print --project /path/to/project --permission-mode bypassPermissions

# Resume a session
cc --resume session-uuid
```

---

## Option B: Global Setup (All Claude Code Runs)

If you want every Claude Code invocation to use Synapse:

### Step 1: Create a global wrapper

```bash
cat > /usr/local/bin/claude-synapse << 'WRAPPER'
#!/bin/bash
SYNAPSE_ROOT="$HOME/synapse"
SYNAPSE_AGENT_NAME="claude-code"
SYNAPSE_MEM="$HOME/.synapse-memory-global"
exec "$SYNAPSE_ROOT/scripts/claude-code-wrapper.sh" "$@"
WRAPPER
chmod +x /usr/local/bin/claude-synapse
```

### Step 2: Alias it

```bash
alias cc="claude-synapse"
```

This catches every `cc` invocation, even from tools that call `claude` indirectly.

---

## Reflection Prompts (What to Answer)

After Claude Code exits, the wrapper will ask you 4 quick questions:

```
What did you work on?
→ Brief description of what you built or fixed

What broke or surprised me?
→ Anything unexpected that happened

What would I do differently?
→ Any process or approach change for next time

Pattern worth surfacing?
→ Anything worth sharing with the fleet
```

These map to the Technical reflection format. Questions are inline — no extra prompts to dismiss.

**To skip:** press Enter on any question to accept the default ("Nothing unexpected", "No changes", etc.).

---

## Shared Memory vs Local Memory

### Per-project (Option A)

Each project has its own `.synapse-memory/` directory. Reflections from different projects are namespaced by task label (includes project name).

**Use when:** you have multiple independent projects and want isolated memory per project.

### Global (Option B)

All Claude Code sessions write to the same `~/.synapse-memory-global/`. All reflections feed the same synthesis pipeline.

**Use when:** you want Claude Code to contribute to the fleet's growth system across all projects.

### Hybrid (Recommended for teams)

Use a shared path (e.g., a synced folder or network drive):

```bash
SYNAPSE_MEM="/shared/ai-memory/claude-code"
```

Then the whole team benefits from Claude Code's learnings flowing into shared guidance.

---

## Synthesis Integration

Add this to your synthesis cron:

```bash
# ~/.crontab
# Run synthesis at 4AM (adjust for your timezone)
0 4 * * * SYNAPSE_WORKSPACE=/path/to/synapse ~/.synapse/scripts/synthesis.sh >> ~/.synapse/logs/synthesis.log 2>&1
```

The synthesis script reads all `memory/reflections/*/` directories — including `memory/reflections/claude-code/`. Your Claude Code reflections are processed alongside other agents automatically.

---

## Running Without Synapse

If you want to run Claude Code without Synapse integration at any point:

```bash
# Direct call (no wrapper)
claude --print --permission-mode bypassPermissions

# Or use the wrapper with SYNAPSE_MEM disabled
SYNAPSE_MEM="" ./synapse/scripts/claude-code-wrapper.sh --print
```

---

## Troubleshooting

### "No .synapse-workspace found"
The wrapper didn't find a config file. Either:
1. Create `.synapse-workspace` in your project (Option A)
2. Set `SYNAPSE_CONFIG` env var pointing to your config
3. Set `SYNAPSE_WORKSPACE` env var with the memory path directly

### "jq not found"
```bash
brew install jq
```

### Reflection not written
Check `/tmp/synapse-session-*.log` for errors. The wrapper logs everything there.

### Startup gate failing on first run
First run has no prior session — the gate should pass trivially. If it fails, check:
- `memory/chronicles/` directory exists
- `memory/synapse/session-log.md` exists and has the header
- `memory/synapse/proposals/` and `memory/synapse/chronicle-reflections/` directories exist

Run the init manually:
```bash
cd ~/synapse
mkdir -p memory/chronicles memory/synapse/proposals memory/synapse/chronicle-reflections
touch memory/synapse/session-log.md memory/synapse/processed-registry.jsonl memory/synapse/file-mtimes.json
echo "# Synapse Session Log" > memory/synapse/session-log.md
echo "{}" > memory/synapse/file-mtimes.json
```

---

## Session Logging

All session activity is logged to `/tmp/synapse-session-{SESSION_ID}.log`. This includes:
- Startup gate output
- Shutdown gate output
- Any errors

Logs are not persisted to the Synapse memory directory — they're temporary. Keep them if you need to debug; delete them to save space.

---

## Customizing the Wrapper

### Remove interactive prompts

If you want fully automated sessions (no prompts), edit `claude-code-wrapper.sh` and replace the `read` section with default values:

```bash
WORK_SUMMARY="claude-code session completed"
WHAT_BROKE="Nothing unexpected"
WHAT_DIFFERENT="No changes"
FLAG_FOR="None"
```

### Add custom guidance at session start

Edit the wrapper to prepend your project-specific system prompt:

```bash
CUSTOM_PROMPT=$(cat .claude-code-prompt 2>/dev/null || echo "")

claude "$@" <<< "$CUSTOM_PROMPT"
```

### Change reflection format

Claude Code defaults to Technical format. To use a different format, change the reflection block in the wrapper to match Strategic, Creative, or Assistant templates from `scripts/template-reflections/`.

---

## Next Steps

1. Run your first session through the wrapper
2. Check `memory/reflections/claude-code/YYYY-MM-DD.md` for your reflection
3. Review `memory/guidance/shared.md` after a few sessions to see patterns emerge
4. Run synthesis manually: `./scripts/synthesis.sh --dry-run` to see what it would generate

---

*For the full system specification, see [SPEC.md](../SPEC.md).*