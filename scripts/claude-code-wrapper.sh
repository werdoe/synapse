#!/bin/bash
# ============================================================
# Synapse Wrapper for Claude Code
# Run this instead of `claude --print` to add Synapse lifecycle.
#
# Features:
# - Guidance digest at session start (your latest patterns)
# - Session lifecycle tracking (open-date, session ID)
# - Reflection written after every session (interactive or env-var)
# - Shutdown gate on exit
#
# Usage:
#   cc --print --permission-mode bypassPermissions
#   cc --print --project /path/to/project
#   cc --resume session-id
#
# Non-interactive (env vars):
#   SYNAPS E_SUMMARY="..." SYNAPSE_BROKE="..." SYNAPSE_DIFFERENT="..." cc ...
#
# Interactive (prompts after session):
#   SYNAPSE_INTERACTIVE=1 cc ...
# ============================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYNAPSE_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# ============================================================
# Config Discovery
# ============================================================
find_synapse_config() {
  local dir="$PWD"
  for i in {1..5}; do
    [[ -f "$dir/.synapse-workspace" ]] && echo "$dir/.synapse-workspace" && return 0
    dir="$(dirname "$dir")"
  done
  [[ -f "${HOME}/.synapse-workspace" ]] && echo "${HOME}/.synapse-workspace" && return 0
  return 1
}

SYNAPSE_CONFIG="${SYNAPSE_WORKSPACE:-$(find_synapse_config 2>/dev/null || echo "")}"
SYNAPSE_MEM="${SYNAPSE_MEM:-${SYNAPSE_ROOT}/memory}"
SYNAPSE_AGENT_NAME="${SYNAPSE_AGENT_NAME:-claude-code}"
SYNAPSE_INTERACTIVE="${SYNAPSE_INTERACTIVE:-0}"

if [[ ! -f "$SYNAPSE_CONFIG" && -z "${SYNAPSE_WORKSPACE:-}" ]]; then
  echo "[SYNAPSE] No .synapse-workspace found. Running without Synapse."
  echo "[SYNAPSE] Create .synapse-workspace in your project. See docs/CLAUDE-CODE-SETUP.md"
  echo ""
  claude "$@"
  exit $?
fi

[[ -f "$SYNAPSE_CONFIG" ]] && source "$SYNAPSE_CONFIG"

export SYNAPSE_WORKSPACE="${SYNAPSE_CONFIG}"
export SYNAPSE_ROOT

# ============================================================
# Init
# ============================================================
init_synapse() {
  local mem="$SYNAPSE_MEM"
  mkdir -p "$mem/guidance" "$mem/reflections/${SYNAPSE_AGENT_NAME}"
  mkdir -p "$mem/chronicles" "$mem/synapse/proposals" "$mem/synapse/chronicle-reflections"
  touch "$mem/synapse/session-log.md" "$mem/synapse/processed-registry.jsonl" 2>/dev/null || true
  [[ ! -f "$mem/synapse/file-mtimes.json" ]] && echo '{}' > "$mem/synapse/file-mtimes.json"
  grep -q "^# Synapse Session Log" "$mem/synapse/session-log.md" 2>/dev/null || { echo "# Synapse Session Log" > "$mem/synapse/session-log.md"; echo "" >> "$mem/synapse/session-log.md"; }
}

init_synapse

# ============================================================
# Session Info
# ============================================================
OPEN_DATE=$(date +%Y-%m-%d)
OPEN_DATE_YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
HHMM=$(date +%H%M)
SESSION_CANDIDATE="${OPEN_DATE}-${HHMM}"
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M)

# ============================================================
# Header
# ============================================================
echo ""
echo "═══════════════════════════════════════════"
echo "SYNAPSE — Claude Code Session"
echo "═══════════════════════════════════════════"
echo "  Open date:  $OPEN_DATE"
echo "  Session ID: $SESSION_CANDIDATE"
echo "  Agent:      $SYNAPSE_AGENT_NAME"
echo ""

# ============================================================
# GUIDANCE DIGEST — show before each session
# ============================================================
echo "── Synapse Guidance (latest patterns) ──"

guidance_file="${SYNAPSE_MEM}/guidance/${SYNAPSE_AGENT_NAME}.md"
shared_guidance="${SYNAPSE_MEM}/guidance/shared.md"

print_guidance() {
  local file="$1"
  local label="$2"
  if [[ -f "$file" ]]; then
    local count
    count=$(grep -c "^| P-" "$file" 2>/dev/null || echo "0")
    if [[ "$count" -gt 0 ]]; then
      echo "  ${label} (last ${count} entries):"
      grep "^| P-" "$file" 2>/dev/null | tail -5 | while IFS='|' read -r _ key rule _; do
        key=$(echo "$key" | tr -d ' ' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        rule=$(echo "$rule" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        [[ -n "$key" && -n "$rule" && "$key" != "Key" ]] && echo "    · $key — $rule"
      done
    else
      echo "  ${label}: (no entries yet)"
    fi
  else
    echo "  ${label}: (file not found)"
  fi
}

print_guidance "$guidance_file" "Personal"
print_guidance "$shared_guidance" "Shared"

echo ""

# ============================================================
# Write preflight-date
# ============================================================
PREFLIGHT_DATE="${SYNAPSE_MEM}/synapse/.preflight-date"
echo "{\"open_date\": \"$OPEN_DATE\", \"open_date_yesterday\": \"$OPEN_DATE_YESTERDAY\", \"session_candidate\": \"$SESSION_CANDIDATE\"}" > "$PREFLIGHT_DATE"

# ============================================================
# Chronicle
# ============================================================
CHRONICLE="${SYNAPSE_MEM}/chronicles/${OPEN_DATE}.md"
[[ ! -f "$CHRONICLE" ]] && echo "# Chronicle — ${OPEN_DATE}" > "$CHRONICLE" && echo "" >> "$CHRONICLE"
echo "[${TIMESTAMP}] Claude Code session opened (agent: $SYNAPSE_AGENT_NAME)" >> "$CHRONICLE"

# ============================================================
# Session markers
# ============================================================
SESSION_OPEN_MARKER="${SYNAPSE_MEM}/synapse/.session-open-${SESSION_CANDIDATE}"
SESSION_TYPE_MARKER="${SYNAPSE_MEM}/synapse/.session-type-${SESSION_CANDIDATE}"

echo "{\"opened_at\": \"$TIMESTAMP\", \"gate_version\": \"2.0\", \"agent\": \"$SYNAPSE_AGENT_NAME\"}" > "$SESSION_OPEN_MARKER"
echo "active" > "$SESSION_TYPE_MARKER"

echo "  ✓ Synapse session open"
echo ""

# ============================================================
# Spawn Claude Code
# ============================================================
LOGFILE="/tmp/synapse-session-${SESSION_CANDIDATE}.log"

echo "── Spawning Claude Code ──"
claude "$@" 2>&1 | tee -a "$LOGFILE"
CLAUDE_EXIT=${PIPESTATUS[0]}

echo ""
echo "── Claude Code exited (code: $CLAUDE_EXIT) ──"

# ============================================================
# Detect task from args
# ============================================================
TASK_LABEL="claude-code session"
i=0
for arg in "$@"; do
  if [[ "$arg" == "--project" ]]; then
    next_idx=$((i + 1))
    next_arg="${@:$next_idx:1}"
    if [[ -n "$next_arg" && "$next_arg" != --* ]]; then
      TASK_LABEL="$(basename "$next_arg")/claude-code"
    fi
  fi
  i=$((i + 1))
done

# ============================================================
# Write Reflection
# ============================================================
REFLECTION_FILE="${SYNAPSE_MEM}/reflections/${SYNAPSE_AGENT_NAME}/${OPEN_DATE}.md"

if [[ -f "$REFLECTION_FILE" ]]; then
  ENTRY_COUNT=$(grep -c "^## Reflection —" "$REFLECTION_FILE" 2>/dev/null || echo "0")
else
  ENTRY_COUNT=0
  echo "# Synapse Reflections — ${OPEN_DATE}" > "$REFLECTION_FILE"
  echo "" >> "$REFLECTION_FILE"
fi

N=$((ENTRY_COUNT + 1))

# Build reflection content
WORK_SUMMARY="${SYNAPSE_SUMMARY:-}"
WHAT_BROKE="${SYNAPSE_BROKE:-}"
WHAT_DIFFERENT="${SYNAPSE_DIFFERENT:-}"
FLAG_FOR="${SYNAPSE_FLAG_FOR:-}"

if [[ "$SYNAPSE_INTERACTIVE" == "1" && -z "$SYNAPSE_SUMMARY" ]]; then
  echo ""
  echo "── Synapse Reflection ──"
  echo "(press Enter to accept default)"
  echo ""
  
  read -p "What did you work on? [$TASK_LABEL] " input
  WORK_SUMMARY="${input:-$TASK_LABEL}"
  
  read -p "What broke or surprised you? [Nothing unexpected] " input
  WHAT_BROKE="${input:-Nothing unexpected}"
  
  read -p "What would you do differently? [No changes] " input
  WHAT_DIFFERENT="${input:-No changes}"
  
  read -p "Pattern worth surfacing? [None] " input
  FLAG_FOR="${input:-None}"
fi

WORK_SUMMARY="${WORK_SUMMARY:-$TASK_LABEL}"
WHAT_BROKE="${WHAT_BROKE:-Nothing unexpected}"
WHAT_DIFFERENT="${WHAT_DIFFERENT:-No changes}"
FLAG_FOR="${FLAG_FOR:-None}"

cat >> "$REFLECTION_FILE" << EOF

## Reflection — ${HHMM} — ${N} — ${TASK_LABEL}

### What did I do?
${WORK_SUMMARY}

### What broke or surprised me?
${WHAT_BROKE}

### What would I do differently?
${WHAT_DIFFERENT}

### Does this challenge any of my personal guidance?
No

### Flag for:
${FLAG_FOR}
EOF

echo "  ✓ Reflection written (#${N})"

# ============================================================
# Update chronicle
# ============================================================
echo "[${TIMESTAMP}] Claude Code session closed (exit: $CLAUDE_EXIT, reflection: #${N})" >> "$CHRONICLE"

# ============================================================
# Shutdown gate
# ============================================================
echo ""
echo "── Shutdown gate ──"
"$SYNAPSE_ROOT/scripts/shutdown-gate.sh" >> "$LOGFILE" 2>&1 || {
  echo "  ⚠️  Shutdown gate had warnings"
}

echo ""
echo "═══════════════════════════════════════════"
echo "Synapse — Session ${SESSION_CANDIDATE} closed"
echo "═══════════════════════════════════════════"
echo ""

exit $CLAUDE_EXIT