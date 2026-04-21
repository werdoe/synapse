#!/bin/bash
# ============================================================
# Synapse Session Startup Gate
# Verifies prior session closed cleanly and all preflight
# artifacts are in place before accepting new work.
#
# Usage: ./startup-gate.sh
# Returns: 0 on pass, 1 on fail (with message)
# ============================================================

set -euo pipefail

WORKSPACE="${SYNAPSE_WORKSPACE:-${HOME}/.openclaw/workspace}"
MEMORY="${WORKSPACE}/memory"
SYNAPSE="${MEMORY}/synapse"
ACTIVE="${MEMORY}/ACTIVE.md"

# ============================================================
# Helpers
# ============================================================
PASS_COUNT=0
FAIL_COUNT=0
WARN_COUNT=0

check_pass() {
  echo "  ✓ $1"
  PASS_COUNT=$((PASS_COUNT + 1))
}

check_warn() {
  echo "  ⚠ $1"
  WARN_COUNT=$((WARN_COUNT + 1))
}

check_fail() {
  echo "  ✗ $1"
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo ""
echo "═══════════════════════════════════════════"
echo "SYNAPSE STARTUP GATE"
echo "═══════════════════════════════════════════"

# ============================================================
# Step 0: Read locked open-date from .preflight-date
# ============================================================
PREFLIGHT_DATE="${SYNAPSE}/.preflight-date"

if [[ ! -f "$PREFLIGHT_DATE" ]]; then
  echo "ERROR: .preflight-date not found — Stage 1 preflight was not run."
  echo "Run Stage 1 preflight before starting the gate."
  exit 1
fi

OPEN_DATE=$(jq -r '.open_date' "$PREFLIGHT_DATE" 2>/dev/null || echo "")
OPEN_DATE_YESTERDAY=$(jq -r '.open_date_yesterday' "$PREFLIGHT_DATE" 2>/dev/null || echo "")
SESSION_CANDIDATE=$(jq -r '.session_candidate' "$PREFLIGHT_DATE" 2>/dev/null || echo "")

if [[ -z "$OPEN_DATE" || -z "$OPEN_DATE_YESTERDAY" ]]; then
  echo "ERROR: .preflight-date is corrupted — missing open_date fields."
  exit 1
fi

echo "  Locked open-date: $OPEN_DATE"
echo "  Session ID: $SESSION_CANDIDATE"

# ============================================================
# CHECK 1: Chronicle exists for open-date
# ============================================================
echo ""
echo "── CHECK 1: Chronicle ──"

CHRONICLE="${MEMORY}/chronicles/${OPEN_DATE}.md"
if [[ -f "$CHRONICLE" ]]; then
  check_pass "chronicles/${OPEN_DATE}.md exists"
else
  check_fail "chronicles/${OPEN_DATE}.md missing — create with: echo '# Chronicle — ${OPEN_DATE}' > \"$CHRONICLE\""
fi

# ============================================================
# CHECK 2: ACTIVE.md freshness (< 8 hours)
# ============================================================
echo ""
echo "── CHECK 2: ACTIVE.md freshness ──"

if [[ ! -f "$ACTIVE" ]]; then
  check_fail "ACTIVE.md not found at ${ACTIVE}"
else
  # Get mtime in seconds
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f %m "$ACTIVE")
  else
    mtime=$(stat -c %Y "$ACTIVE")
  fi
  now=$(date +%s)
  age_hours=$(( (now - mtime) / 3600 ))
  
  if [[ $age_hours -lt 8 ]]; then
    check_pass "ACTIVE.md is ${age_hours}h old (< 8h threshold)"
  else
    check_warn "ACTIVE.md is ${age_hours}h old (> 8h) — update before active work"
  fi
fi

# ============================================================
# CHECK 3: Proposals dispositioned for open-date-yesterday
# ============================================================
echo ""
echo "── CHECK 3: Proposals dispositioned ──"

REVIEWED_FILE="${SYNAPSE}/proposals/${OPEN_DATE_YESTERDAY}.reviewed"
PROPOSALS_FILE="${SYNAPSE}/proposals/${OPEN_DATE_YESTERDAY}.md"

if [[ ! -f "$PROPOSALS_FILE" ]]; then
  check_pass "No proposals file for ${OPEN_DATE_YESTERDAY} — trivial pass"
elif [[ -f "$REVIEWED_FILE" ]]; then
  # Verify all candidates have disposition lines
  candidate_count=$(grep -c "^## Candidate" "$PROPOSALS_FILE" 2>/dev/null || echo "0")
  disposition_count=$(grep -c "^CANDIDATE-" "$REVIEWED_FILE" 2>/dev/null || echo "0")
  
  if [[ "$candidate_count" -eq 0 ]]; then
    check_pass "Proposals file has no candidates — trivial pass"
  elif [[ "$disposition_count" -ge "$candidate_count" ]]; then
    check_pass "${disposition_count}/${candidate_count} candidates dispositioned"
  else
    check_fail "${disposition_count}/${candidate_count} candidates dispositioned — missing .reviewed entry"
  fi
else
  check_fail "Proposals exist for ${OPEN_DATE_YESTERDAY} but no .reviewed file"
  echo "    → Write dispositions: memory/synapse/proposals/${OPEN_DATE_YESTERDAY}.reviewed"
fi

# ============================================================
# CHECK 4: Open contradictions have review_notes
# ============================================================
echo ""
echo "── CHECK 4: Contradiction review_notes ──"

CONTRADICTION_LOG="${SYNAPSE}/contradiction-log.md"

if [[ ! -f "$CONTRADICTION_LOG" ]]; then
  check_pass "No contradiction log — trivial pass"
else
  open_count=$(grep -c "^## Contradiction" "$CONTRADICTION_LOG" 2>/dev/null || echo "0")
  
  if [[ "$open_count" -eq 0 ]]; then
    check_pass "No open contradictions — trivial pass"
  else
    # Check each OPEN entry has a review_note
    missing=0
    in_open=false
    has_note=false
    
    while IFS= read -r line; do
      if echo "$line" | grep -q "^## Contradiction"; then
        in_open=true
        has_note=false
      elif echo "$line" | grep -q "^## " && [[ "$in_open" == "true" ]]; then
        # Next section started
        if [[ "$has_note" == "false" ]]; then
          missing=$((missing + 1))
        fi
        in_open=false
      elif echo "$line" | grep -q "^Status: OPEN"; then
        # Currently in an open entry, will check for review_note
        :
      elif echo "$line" | grep -q "^review_note:"; then
        has_note=true
      fi
    done < "$CONTRADICTION_LOG"
    
    if [[ $missing -gt 0 ]]; then
      check_fail "$missing OPEN contradiction(s) without review_note — add review_note at startup"
    else
      check_pass "All OPEN contradictions have review_notes"
    fi
  fi
fi

# ============================================================
# CHECK 5: MEMORY.md freshness (warning only)
# ============================================================
echo ""
echo "── CHECK 5: MEMORY.md freshness ──"

MEMORY_MD="${WORKSPACE}/MEMORY.md"

if [[ ! -f "$MEMORY_MD" ]]; then
  check_warn "MEMORY.md not found — create and seed from chronicles"
else
  if [[ "$(uname)" == "Darwin" ]]; then
    mtime=$(stat -f %m "$MEMORY_MD")
  else
    mtime=$(stat -c %Y "$MEMORY_MD")
  fi
  now=$(date +%s)
  days_stale=$(( (now - mtime) / 86400 ))
  
  if [[ $days_stale -lt 3 ]]; then
    check_pass "MEMORY.md is ${days_stale}d old (< 3d — clean)"
  else
    check_warn "MEMORY.md is ${days_stale}d stale — review and update before active work"
  fi
fi

# ============================================================
# CHECK 6: NOTES.md overdue items
# ============================================================
echo ""
echo "── CHECK 6: NOTES.md overdue items ──"

NOTES="${WORKSPACE}/NOTES.md"

if [[ ! -f "$NOTES" ]]; then
  check_pass "NOTES.md not found — no overdue items"
else
  today_ts=$(date +%s)
  
  # Look for Next Review dates in the format: {YYYY-MM-DD}
  overdue_found=false
  while IFS= read -r line; do
    if echo "$line" | grep -q "Next Review"; then
      date_str=$(echo "$line" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}' | tail -1)
      if [[ -n "$date_str" ]]; then
        review_ts=$(date -j -f "%Y-%m-%d" "$date_str" +%s 2>/dev/null || echo "0")
        if [[ $review_ts -gt 0 && $review_ts -lt $today_ts ]]; then
          check_fail "Overdue review item found: $line"
          overdue_found=true
        fi
      fi
    fi
  done < "$NOTES"
  
  if [[ "$overdue_found" == "false" ]]; then
    check_pass "No overdue items in NOTES.md"
  fi
fi

# ============================================================
# CHECK 7: No orphaned session markers
# ============================================================
echo ""
echo "── CHECK 7: Orphaned session markers ──"

ORPHAN_MARKERS=$(find "$SYNAPSE" -maxdepth 1 -name ".session-open-*" -type f 2>/dev/null || echo "")

if [[ -z "$ORPHAN_MARKERS" ]]; then
  check_pass "No orphaned session markers"
else
  now_ts=$(date +%s)
  orphaned_any=false
  warning_any=false
  
  for marker in $ORPHAN_MARKERS; do
    marker_name=$(basename "$marker")
    
    # Get embedded session_candidate from filename: .session-open-{session_candidate}
    session_id="${marker_name#.session-open-}"
    
    # Check if this is the CURRENT session's own marker
    if [[ "$marker_name" == ".session-open-${SESSION_CANDIDATE}" ]]; then
      continue  # Current session — skip, don't count as orphan
    fi
    
    # Get mtime
    if [[ "$(uname)" == "Darwin" ]]; then
      marker_mtime=$(stat -f %m "$marker")
    else
      marker_mtime=$(stat -c %Y "$marker")
    fi
    
    age_hours=$(( (now_ts - marker_mtime) / 3600 ))
    
    # Check if session-log has this session ID
    session_log_entry=$(grep -l "Session ID: ${session_id}" "${SYNAPSE}/session-log.md" 2>/dev/null || echo "")
    
    if [[ -n "$session_log_entry" ]]; then
      check_pass "Prior session ${session_id} closed cleanly"
    else
      if [[ $age_hours -ge 24 ]]; then
        check_fail "Orphaned marker ≥24h: ${marker_name} — hard fail. Resolution: write manual close entry to session-log, then delete marker + .preflight-date + .session-type-"
        orphaned_any=true
      else
        check_warn "Orphaned marker <24h: ${marker_name} — warning only. Session can open but cannot close until resolved."
        warning_any=true
      fi
    fi
  done
  
  if [[ "$orphaned_any" == "true" ]]; then
    echo ""
    echo "  → Write manual close: memory/synapse/session-log.md (see SPEC.md CHECK 7)"
    echo "  → Delete: .session-open-*, .preflight-date (if session_candidate match), .session-type-*"
  fi
fi

# ============================================================
# Summary
# ============================================================
echo ""
echo "═══════════════════════════════════════════"

if [[ $FAIL_COUNT -gt 0 ]]; then
  echo "🔒 Startup gate — ${FAIL_COUNT} item(s) need attention:"
  echo ""
  echo "Do not proceed. Resolve failures above, then re-run:"
  echo "  ./scripts/startup-gate.sh"
  exit 1
elif [[ $WARN_COUNT -gt 0 ]]; then
  echo "✅ Startup gate clear — $(date -u +%Y-%m-%dT%H:%M:%SZ) (${WARN_COUNT} warning(s))"
  echo "Session ID: $SESSION_CANDIDATE"
  echo ""
  echo "⚠️  Warnings must be resolved before /new:"
  echo "  - Update ACTIVE.md if stale"
  echo "  - Refresh MEMORY.md if stale"
  echo "  - Resolve orphaned marker warnings before session close"
  exit 0
else
  echo "✅ Startup gate clear — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "Session ID: $SESSION_CANDIDATE"
  echo "Ready."
  exit 0
fi