#!/bin/bash
# ============================================================
# Synapse Session Shutdown Gate
# Verifies reflection written, session-log entry updated,
# and all per-session enforcement satisfied.
#
# Usage: ./shutdown-gate.sh
# Returns: 0 on pass, 1 on fail (with message)
# ============================================================

set -euo pipefail

WORKSPACE="${SYNAPSE_WORKSPACE:-${HOME}/.openclaw/workspace}"
MEMORY="${WORKSPACE}/memory"
SYNAPSE="${MEMORY}/synapse"
REFLECTIONS="${MEMORY}/reflections"
SESSION_LOG="${SYNAPSE}/session-log.md"
SESSION_TYPE_FILE="${SYNAPSE}/.session-type-${SESSION_ID:-unknown}"

# ============================================================
# Helpers
# ============================================================
PASS_COUNT=0
FAIL_COUNT=0

check_pass() {
  echo "  ✓ $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

check_fail() {
  echo "  ✗ $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo ""
echo "═══════════════════════════════════════════"
echo "SYNAPSE SHUTDOWN GATE"
echo "═══════════════════════════════════════════"

# ============================================================
# Get session info from .preflight-date
# ============================================================
PREFLIGHT_DATE="${SYNAPSE}/.preflight-date"

if [[ ! -f "$PREFLIGHT_DATE" ]]; then
  echo "ERROR: .preflight-date not found. Run startup gate first."
  exit 1
fi

OPEN_DATE=$(jq -r '.open_date' "$PREFLIGHT_DATE" 2>/dev/null || echo "")
OPEN_DATE_YESTERDAY=$(jq -r '.open_date_yesterday' "$PREFLIGHT_DATE" 2>/dev/null || echo "")
SESSION_CANDIDATE=$(jq -r '.session_candidate' "$PREFLIGHT_DATE" 2>/dev/null || echo "")

echo "  Session open-date: $OPEN_DATE"
echo "  Session ID: $SESSION_CANDIDATE"

# ============================================================
# CHECK 0: Session-type declaration file
# ============================================================
echo ""
echo "── CHECK 0: Session-type declaration ──"

# Find the session-type file for this session
SESSION_TYPE_MARKER=$(find "$SYNAPSE" -maxdepth 1 -name ".session-type-${SESSION_CANDIDATE}" -type f 2>/dev/null || echo "")

if [[ -z "$SESSION_TYPE_MARKER" ]]; then
  # Try without session ID prefix (backwards compat)
  SESSION_TYPE_MARKER=$(find "$SYNAPSE" -maxdepth 1 -name ".session-type-*" -newer "$PREFLIGHT_DATE" -type f 2>/dev/null | head -1 || echo "")
fi

if [[ -n "$SESSION_TYPE_MARKER" ]]; then
  SESSION_TYPE=$(cat "$SESSION_TYPE_MARKER" 2>/dev/null || echo "unknown")
  echo "  Session type: $SESSION_TYPE"
  check_pass "Session-type declaration exists: $(basename "$SESSION_TYPE_MARKER")"
else
  check_fail "Session-type declaration file missing — write memory/synapse/.session-type-${SESSION_CANDIDATE} (active or heartbeat-only)"
  SESSION_TYPE="unknown"
fi

# ============================================================
# CHECK 1: Session-log entry does not already exist
# ============================================================
echo ""
echo "── CHECK 1: Session-log entry ──"

if [[ ! -f "$SESSION_LOG" ]]; then
  touch "$SESSION_LOG"
  echo "# Synapse Session Log" >> "$SESSION_LOG"
  echo "" >> "$SESSION_LOG"
fi

# Check for existing entry for this session
existing_entry=$(grep -c "Session ID: ${SESSION_CANDIDATE}" "$SESSION_LOG" 2>/dev/null || echo "0")
if [[ "$existing_entry" -gt 0 ]]; then
  check_fail "Session ${SESSION_CANDIDATE} already has a log entry — cannot close twice"
else
  check_pass "No prior log entry for ${SESSION_CANDIDATE}"
fi

# ============================================================
# CHECK 2: Kvothe reflection (if active session)
# ============================================================
echo ""
echo "── CHECK 2: Kvothe reflection ──"

KVOTHE_REFLECTION="${REFLECTIONS}/kvothe/${OPEN_DATE}.md"

if [[ "$SESSION_TYPE" == "heartbeat-only" ]]; then
  check_pass "Heartbeat-only session — reflection skipped, logged in session-log"
elif [[ "$SESSION_TYPE" == "active" || "$SESSION_TYPE" == "unknown" ]]; then
  if [[ -f "$KVOTHE_REFLECTION" ]]; then
    # Count active closes for this open-date in session-log
    prior_closes=$(grep -c "Session type: active" "$SESSION_LOG" 2>/dev/null || echo "0")
    expected=$((prior_closes + 1))  # +1 for current session if active
    
    reflection_count=$(grep -c "^## Reflection —" "$KVOTHE_REFLECTION" 2>/dev/null || echo "0")
    
    if [[ $reflection_count -ge $expected ]]; then
      check_pass "Kvothe reflection present (${reflection_count} entries, expected ≥${expected})"
    else
      check_fail "Kvothe has ${reflection_count} reflection(s) but ${expected} expected (active closes + current)"
    fi
  else
    if [[ "$SESSION_TYPE" == "active" ]]; then
      check_fail "Active session — reflection missing at ${KVOTHE_REFLECTION}"
    else
      check_warn "Reflection file not found (session-type unknown — treat as heartbeat unless verified)"
    fi
  fi
fi

# ============================================================
# CHECK 3: Archive trigger review
# ============================================================
echo ""
echo "── CHECK 3: Archive trigger review ──"

# Check GENERAL_LEARNINGS and NEEMCLAW_LEARNINGS
GENERAL_LEARNINGS="${WORKSPACE}/GENERAL_LEARNINGS.md"
NEEMCLAW_LEARNINGS="${WORKSPACE}/NEEMCLAW_LEARNINGS.md"

general_check="not checked"
neemclaw_check="not checked"

if [[ -f "$GENERAL_LEARNINGS" ]]; then
  # Look for recent entries with today's date
  today_entries=$(grep -c "^## G[0-9]" "$GENERAL_LEARNINGS" 2>/dev/null || echo "0")
  general_check="trigger fired → $today_entries new entries written"
fi

if [[ -f "$NEEMCLAW_LEARNINGS" ]]; then
  today_entries=$(grep -c "^## N[0-9]" "$NEEMCLAW_LEARNINGS" 2>/dev/null || echo "0")
  neemclaw_check="trigger fired → $today_entries new entries written"
fi

echo "  General learnings: $general_check"
echo "  NeemClaw learnings: $neemclaw_check"
check_pass "Archive review complete (trigger test applied)"

# ============================================================
# CHECK 4: Kilvin spawn verification (if any spawns occurred)
# ============================================================
echo ""
echo "── CHECK 4: Kilvin spawn verification ──"

SPAWN_MARKERS=$(find "$SYNAPSE" -maxdepth 1 -name ".kilvin-spawn-${OPEN_DATE}-*" -type f 2>/dev/null || echo "")
SPAWN_COUNT=0

if [[ -z "$SPAWN_MARKERS" ]]; then
  check_pass "No Kilvin spawns on ${OPEN_DATE} — trivial pass"
else
  for marker in $SPAWN_MARKERS; do
    marker_name=$(basename "$marker")
    spawned_at=$(jq -r '.spawned_at' "$marker" 2>/dev/null || echo "")
    task=$(jq -r '.task' "$marker" 2>/dev/null || echo "")
    session_id=$(jq -r '.session_id' "$marker" 2>/dev/null || echo "")
    echo "  Found: ${marker_name} — session: ${session_id}, task: ${task}"
    SPAWN_COUNT=$((SPAWN_COUNT + 1))
  done
  
  # Count reflections for Kilvin on this open-date
  KILVIN_REFLECTION="${REFLECTIONS}/kilvin/${OPEN_DATE}.md"
  
  if [[ -f "$KILVIN_REFLECTION" ]]; then
    reflection_count=$(grep -c "^## Reflection —" "$KILVIN_REFLECTION" 2>/dev/null || echo "0")
  else
    reflection_count=0
  fi
  
  echo "  Spawn markers: $SPAWN_COUNT | Reflection entries: $reflection_count"
  
  if [[ $SPAWN_COUNT -gt $reflection_count ]]; then
    check_fail "$SPAWN_COUNT spawn markers but only $reflection_count reflection entries — write backup entries for missing"
  else
    check_pass "Kilvin spawns verified: $SPAWN_COUNT markers, $reflection_count reflections"
  fi
  
  # KILVIN_MEMORY.md update check (spawn-day requirement)
  KILVIN_MEMORY="${WORKSPACE}/workspace-kilvin/KILVIN_MEMORY.md"
  if [[ -f "$KILVIN_MEMORY" ]]; then
    update_stamp=$(grep -o "Last updated: [0-9-]*" "$KILVIN_MEMORY" | tail -1 | awk '{print $3}')
    if [[ "$update_stamp" == "$OPEN_DATE" ]]; then
      check_pass "KILVIN_MEMORY.md updated for ${OPEN_DATE}"
    else
      check_warn "KILVIN_MEMORY.md stamp (${update_stamp:-missing}) ≠ open-date (${OPEN_DATE}) — update with: *Last updated: ${OPEN_DATE} (spawn: ${HHMM})*"
    fi
  else
    check_warn "KILVIN_MEMORY.md not found at ${KILVIN_MEMORY}"
  fi
fi

# ============================================================
# CHECK 5: Write session-log entry (sole writer)
# ============================================================
echo ""
echo "── CHECK 5: Writing session-log entry ──"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  echo "  SKIPPED — gate failures must be resolved before logging close"
else
  # Get current timestamp
  CLOSE_TIMESTAMP=$(date +%Y-%m-%d\ %H:%M)
  HHMM=$(date +%H%M)
  
  # Determine archive review results
  general_fired=false
  neemclaw_fired=false
  
  if [[ -f "$GENERAL_LEARNINGS" ]]; then
    # Count G- entries from today
    today_g_count=$(grep "^## G" "$GENERAL_LEARNINGS" 2>/dev/null | grep -c "$(date +%Y-%m-%d)" || echo "0")
    if [[ $today_g_count -gt 0 ]]; then
      general_fired=true
      general_result="trigger fired → G-entries written"
    fi
  fi
  
  if [[ -f "$NEEMCLAW_LEARNINGS" ]]; then
    today_n_count=$(grep "^## N" "$NEEMCLAW_LEARNINGS" 2>/dev/null | grep -c "$(date +%Y-%m-%d)" || echo "0")
    if [[ $today_n_count -gt 0 ]]; then
      neemclaw_fired=true
      neemclaw_result="trigger fired → N-entries written"
    fi
  fi
  
  # Count proposals reviewed
  REVIEWED_FILE="${SYNAPSE}/proposals/${OPEN_DATE_YESTERDAY}.reviewed"
  if [[ -f "$REVIEWED_FILE" ]]; then
    proposal_count=$(grep -c "^CANDIDATE-" "$REVIEWED_FILE" 2>/dev/null || echo "0")
    proposals_result="${proposal_count} candidates dispositioned"
  else
    proposals_result="no proposals | deferred from prior session"
  fi
  
  # Log entry
  {
    echo "---"
    echo "## Session — ${OPEN_DATE} — ${CLOSE_TIMESTAMP} close"
    echo "Session ID: ${SESSION_CANDIDATE}"
    echo "Session type: ${SESSION_TYPE}"
    echo "- Archive review (GENERAL_LEARNINGS): ${general_result:-no trigger fired}"
    echo "- Archive review (NEEMCLAW_LEARNINGS): ${neemclaw_result:-no trigger fired}"
    echo "- Kvothe reflection: $([[ "$SESSION_TYPE" == "active" ]] && echo "written ${CLOSE_TIMESTAMP}" || echo "heartbeat-only — skipped")"
    echo "- Proposals reviewed: ${proposals_result}"
    echo "- Kilvin spawns (this session): $([[ $SPAWN_COUNT -gt 0 ]] && echo "${SPAWN_COUNT} spawn(s), ${reflection_count} reflections verified" || echo "no spawns this session")"
  } >> "$SESSION_LOG"
  
  check_pass "Session-log entry written for ${SESSION_CANDIDATE}"
fi

# ============================================================
# CHECK 6: Cleanup session markers
# ============================================================
echo ""
echo "── CHECK 6: Cleanup ──"

# Delete session-open marker
SESSION_OPEN_MARKER="${SYNAPSE}/.session-open-${SESSION_CANDIDATE}"
if [[ -f "$SESSION_OPEN_MARKER" ]]; then
  rm -f "$SESSION_OPEN_MARKER"
  check_pass "Deleted: .session-open-${SESSION_CANDIDATE}"
else
  check_pass "Session-open marker already removed (or never created)"
fi

# Delete preflight-date (clean close)
if [[ -f "$PREFLIGHT_DATE" ]]; then
  rm -f "$PREFLIGHT_DATE"
  check_pass "Deleted: .preflight-date"
fi

# Delete session-type marker
if [[ -n "$SESSION_TYPE_MARKER" && -f "$SESSION_TYPE_MARKER" ]]; then
  rm -f "$SESSION_TYPE_MARKER"
  check_pass "Deleted: $(basename "$SESSION_TYPE_MARKER")"
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "═══════════════════════════════════════════"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "🔒 Shutdown gate — ${FAIL_COUNT} item(s) need resolution:"
  echo ""
  echo "Resolve failures above before /new:"
  echo "  - Write missing reflection entries"
  echo "  - Write backup entries for missing Kilvin reflections"
  echo "  - Update KILVIN_MEMORY.md if needed"
  echo ""
  echo "Then re-run: ./scripts/shutdown-gate.sh"
  exit 1
else
  echo "✅ Shutdown gate clear — ${CLOSE_TIMESTAMP}"
  echo "Session ${SESSION_CANDIDATE} closed cleanly."
  exit 0
fi