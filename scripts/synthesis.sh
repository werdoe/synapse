#!/bin/bash
# ============================================================
# Synapse Synthesis Pipeline
# Runs at 4AM daily. Processes all new reflection files,
# generates candidate learnings, updates contradiction log.
# Auto-promotes high-confidence personal candidates.
#
# Usage: ./synthesis.sh [--dry-run]
# ============================================================

set -euo pipefail

WORKSPACE="${SYNAPSE_WORKSPACE:-${HOME}/.openclaw/workspace}"
MEMORY="${WORKSPACE}/memory"
SYNAPSE="${MEMORY}/synapse"
REFLECTIONS="${MEMORY}/reflections"
CHRONICLES="${MEMORY}/chronicles"
GUIDANCE="${MEMORY}/guidance"

LOG="${SYNAPSE}/synthesis.log"

# Runtime state files
FILE_MTIMES="${SYNAPSE}/file-mtimes.json"
PROCESSED_REGISTRY="${SYNAPSE}/processed-registry.jsonl"
SESSION_LOG="${SYNAPSE}/session-log.md"

# Run date
RUN_DATE=$(date +%Y-%m-%d)
RUN_DATE_YESTERDAY=$(date -v-1d +%Y-%m-%d 2>/dev/null || date -d "yesterday" +%Y-%m-%d)
TIMESTAMP=$(date +%Y-%m-%d\ %H:%M)
HHMM=$(date +%H%M)

# Dry run flag
DRY_RUN=false
if [[ "${1:-}" == "--dry-run" ]]; then
  DRY_RUN=true
  echo "[DRY RUN] Synthesis pipeline dry-run initiated at ${TIMESTAMP}"
fi

# ============================================================
# Helpers
# ============================================================
log() {
  echo "[${TIMESTAMP}] $1" | tee -a "$LOG"
}

log_section() {
  echo "" | tee -a "$LOG"
  echo "═══════════════════════════════════════════" | tee -a "$LOG"
  echo "$1" | tee -a "$LOG"
  echo "═══════════════════════════════════════════" | tee -a "$LOG"
}

# ============================================================
# Step 1: Init
# ============================================================
log_section "STEP 1: Initialization"

[[ ! -d "$REFLECTIONS" ]] && log "ERROR: reflections/ not found at ${REFLECTIONS}" && exit 1
[[ ! -f "$PROCESSED_REGISTRY" ]] && touch "$PROCESSED_REGISTRY"
[[ ! -f "$FILE_MTIMES" ]] && echo '{}' > "$FILE_MTIMES"

mkdir -p "${SYNAPSE}/proposals" "${SYNAPSE}/chronicle-reflections"

log "Workspace: ${WORKSPACE} | Run date: ${RUN_DATE} | Registry: $(wc -l < "$PROCESSED_REGISTRY" 2>/dev/null || echo 0) entries"

# ============================================================
# Step 2: Catch-up — determine files to read
# ============================================================
log_section "STEP 2: Catch-up"

READ_LIST=()
CHRONICLE_READ_LIST=()

declare -A CURRENT_MTIMES
if [[ -s "$FILE_MTIMES" ]]; then
  while IFS= read -r line; do
    key=$(echo "$line" | jq -r 'keys[0]' 2>/dev/null || echo "")
    [[ -n "$key" && "$key" != "null" ]] && CURRENT_MTIMES["$key"]=$(echo "$line" | jq -r ".[\"$key\"]" 2>/dev/null || echo "0")
  done < <(jq -c 'to_entries[]' "$FILE_MTIMES" 2>/dev/null || echo "")
fi

while IFS= read -r filepath; do
  agent_dir=$(basename "$(dirname "$filepath")")
  filename=$(basename "$filepath")
  current_mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "0")
  
  if [[ -z "${CURRENT_MTIMES[$filepath]:-}" || "$current_mtime" -gt "${CURRENT_MTIMES[$filepath]}" ]]; then
    READ_LIST+=("$filepath")
    open_date="${filename%.md}"
    chronicle_path="${CHRONICLES}/${open_date}.md"
    [[ -f "$chronicle_path" ]] && CHRONICLE_READ_LIST+=("$chronicle_path")
    log "  → ${agent_dir}/${filename}"
  fi
done < <(find "$REFLECTIONS" -name "*.md" -type f 2>/dev/null)

primary_chronicle="${CHRONICLES}/${RUN_DATE_YESTERDAY}.md"
if [[ -f "$primary_chronicle" ]]; then
  already_added=false
  for c in "${CHRONICLE_READ_LIST[@]:-}"; do [[ "$c" == "$primary_chronicle" ]] && already_added=true && break; done
  [[ "$already_added" == "false" ]] && CHRONICLE_READ_LIST+=("$primary_chronicle")
fi

[[ ${#READ_LIST[@]} -eq 0 ]] && log "No new files. Complete." && log_section "Synthesis complete" && exit 0

log "Files: ${#READ_LIST[@]} | Chronicles: ${#CHRONICLE_READ_LIST[@]}"

# ============================================================
# Step 3: Read files
# ============================================================
log_section "STEP 3: Reading files"

declare -A REFLECTION_CONTENT
declare -A CHRONICLE_CONTENT

for filepath in "${READ_LIST[@]}"; do
  key="$(basename "$(dirname "$filepath")"):$(basename "$filepath")"
  REFLECTION_CONTENT["$key"]=$(cat "$filepath" 2>/dev/null || echo "")
done

for chronicle_path in "${CHRONICLE_READ_LIST[@]:-}"; do
  CHRONICLE_CONTENT["$(basename "$chronicle_path")"]=$(cat "$chronicle_path" 2>/dev/null || echo "")
done

# ============================================================
# Step 4: Dedupe
# ============================================================
log_section "STEP 4: Deduplication"

NEW_ENTRIES=()
for filepath in "${READ_LIST[@]}"; do
  agent_dir=$(basename "$(dirname "$filepath")")
  filename=$(basename "$filepath")
  open_date="${filename%.md}"
  
  # Parse each ## Reflection block
  awk '/## Reflection —/{found=1} found; /^---$/{if(found) exit}' "$filepath" 2>/dev/null | \
  while IFS= read -r block; do
    heading=$(echo "$block" | grep -m1 "## Reflection —" || echo "")
    [[ -z "$heading" ]] && continue
    
    hhmm=$(echo "$heading" | sed 's/.*## Reflection — \([^ ]*\) — \([^ ]*\) —.*/\1/')
    n_val=$(echo "$heading" | sed 's/.*## Reflection — \([^ ]*\) — \([^ ]*\) —.*/\2/')
    entry_id="${agent_dir}::${open_date}::${n_val}::${hhmm}"
    
    grep -qF "$entry_id" "$PROCESSED_REGISTRY" 2>/dev/null && { log "  SKIP: ${entry_id}"; continue; }
    
    log "  NEW: ${entry_id}"
    NEW_ENTRIES+=("${entry_id}|${filepath}|${block}")
  done
done

[[ ${#NEW_ENTRIES[@]} -eq 0 ]] && log "All entries processed." && log_section "Synthesis complete" && exit 0

log "New entries: ${#NEW_ENTRIES[@]}"

# ============================================================
# Step 5: Analysis
# ============================================================
log_section "STEP 5: Analysis"

declare -A AGENT_COUNTS
declare -A PATTERN_AGENTS
PROPOSAL_NUM=1
PROPOSAL_OUTPUT=""
AUTO_PROMOTE_CANDIDATES=()

for entry_data in "${NEW_ENTRIES[@]}"; do
  entry_id=$(echo "$entry_data" | cut -d'|' -f1)
  agent=$(echo "$entry_id" | cut -d':' -f1)
  open_date=$(echo "$entry_id" | cut -d':' -f2)
  n_val=$(echo "$entry_id" | cut -d':' -f3)
  hhmm=$(echo "$entry_id" | cut -d':' -f4)
  block=$(echo "$entry_data" | cut -d'|' -f3-)
  
  AGENT_COUNTS["$agent"]=$(( ${AGENT_COUNTS[$agent]:-0} + 1 ))
  
  # Extract content
  what_broke=$(echo "$block" | grep -A2 "### What broke or surprised me?" | tail -n1 | sed 's/^[[:space:]]*//')
  what_different=$(echo "$block" | grep -A2 "### What would I do differently?" | tail -n1 | sed 's/^[[:space:]]*//')
  flag_for=$(echo "$block" | grep -A2 "### Flag for" | tail -n1 | sed 's/^[[:space:]]*//')
  harder=$(echo "$block" | grep -A2 "### What was harder" | tail -n1 | sed 's/^[[:space:]]*//')
  situation=$(echo "$block" | grep -A2 "### What situation did I handle" | tail -n1 | sed 's/^[[:space:]]*//')
  
  # Determine tier
  tier=3
  if echo "$block" | grep -qi "mistake\|wrong\|failed\|bug\|broke\|error\|correction\|verify\|test\|confirmed\|reproduced\|reproduced"; then
    tier=2
  fi
  
  # Pattern key for cross-agent detection
  pattern=""
  [[ -n "$what_broke" && "$what_broke" != "Nothing unexpected" && "$what_broke" != "None" ]] && pattern="$what_broke"
  [[ -z "$pattern" && -n "$harder" && "$harder" != "Straightforward" ]] && pattern="$harder"
  [[ -z "$pattern" && -n "$situation" ]] && pattern="$situation"
  
  pattern_key=$(echo "$pattern" | tr -d '.,!?' | tr -s ' ' | cut -c1-60 | tr ' ' '-')
  
  if [[ -n "$pattern_key" ]]; then
    if [[ -z "${PATTERN_AGENTS[$pattern_key]:-}" ]]; then
      PATTERN_AGENTS["$pattern_key"]="$agent"
    else
      already_counted=false
      for a in $(echo "${PATTERN_AGENTS[$pattern_key]}" | tr ',' '\n'); do [[ "$a" == "$agent" ]] && already_counted=true && break; done
      [[ "$already_counted" == "false" ]] && PATTERN_AGENTS["$pattern_key"]="${PATTERN_AGENTS[$pattern_key]},$agent"
    fi
  fi
  
  # Build proposals
  if [[ -n "$what_different" && "$what_different" != "No changes" && "$what_different" != "Nothing" ]]; then
    rule_text=$(echo "$what_different" | tr -d '.,!?' | tr -s ' ' | cut -c1-80)
    proposed_key="P-${agent}-$(date +%m%d%H%M%S)"
    
    PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: ${agent}
- type: personal
- proposed_key: ${proposed_key}
- proposed_rule: ${rule_text}
- evidence_tier: ${tier}
- evidence: reflection ${open_date} ${hhmm} ($(echo "$block" | grep -c "verified\|tested\|confirmed\|reproduced" 2>/dev/null || echo 0) - tier ${tier})
- confidence: 0.72
- promotion_path: auto_promote_eligible: $([[ $tier -le 2 ]] && echo "yes" || echo "no")
- related_guidance: (none)
"
    
    # Track auto-promote eligible
    [[ $tier -le 2 ]] && AUTO_PROMOTE_CANDIDATES+=("${proposed_key}|${agent}|${rule_text}|${open_date}|${hhmm}")
    
    PROPOSAL_NUM=$((PROPOSAL_NUM + 1))
  fi
  
  [[ -n "$flag_for" && "$flag_for" != "None" ]] && PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: ${agent}
- type: pattern-worth-examining
- proposed_key: P-${agent}-$(date +%m%d%H%M%S)
- proposed_rule: $(echo "$flag_for" | tr -d '.,!?' | tr -s ' ' | cut -c1-80)
- evidence_tier: ${tier}
- evidence: flagged by ${agent} ${open_date} ${hhmm}
- confidence: 0.68
- promotion_path: manual_review_required: yes
- related_guidance: (none)
" && PROPOSAL_NUM=$((PROPOSAL_NUM + 1))
done

# Cross-agent patterns → shared candidates
for pattern_key in "${!PATTERN_AGENTS[@]}"; do
  agents_str="${PATTERN_AGENTS[$pattern_key]}"
  agent_count=$(echo "$agents_str" | tr ',' '\n' | wc -l | tr -d ' ')
  [[ $agent_count -ge 2 ]] && PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: fleet
- type: shared-candidate
- proposed_key: GS-$(date +%m%d%H%M)
- proposed_rule: $(echo "$pattern_key" | tr '-' ' ')
- evidence_tier: 3
- evidence: ${agent_count} agents: ${agents_str}
- confidence: 0.75
- promotion_path: manual_review_required: yes
- related_guidance: (none)
" && PROPOSAL_NUM=$((PROPOSAL_NUM + 1)) && log "  SHARED: ${pattern_key}"
done

log "Agents: ${!AGENT_COUNTS[*]}"

# ============================================================
# Step 6: Write proposals
# ============================================================
log_section "STEP 6: Proposals"

PROPOSALS_FILE="${SYNAPSE}/proposals/${RUN_DATE}.md"

{
  echo "# Synapse Proposals — ${RUN_DATE}"
  echo "*Generated: ${TIMESTAMP}*"
  echo ""
  echo "## Summary"
  echo "- Entries processed: ${#NEW_ENTRIES[@]}"
  echo "- Agents: ${!AGENT_COUNTS[*]}"
  echo "- Auto-promote eligible: ${#AUTO_PROMOTE_CANDIDATES[@]}"
  echo ""
  echo "## Candidates"
  echo "$PROPOSAL_OUTPUT"
} > "$PROPOSALS_FILE"

log "Written: ${PROPOSALS_FILE} (${PROPOSAL_NUM} candidates)"

# ============================================================
# Step 7: Auto-promote high-confidence personal candidates
# ============================================================
log_section "STEP 7: Auto-promote (tier 1/2, confidence ≥ 0.80)"

PROMOTED_COUNT=0
for candidate in "${AUTO_PROMOTE_CANDIDATES[@]}"; do
  key=$(echo "$candidate" | cut -d'|' -f1)
  agent=$(echo "$candidate" | cut -d'|' -f2)
  rule=$(echo "$candidate" | cut -d'|' -f3)
  open_date=$(echo "$candidate" | cut -d'|' -f4)
  hhmm=$(echo "$candidate" | cut -d'|' -f5)
  
  guidance_file="${GUIDANCE}/${agent}.md"
  
  # Ensure guidance file exists
  if [[ ! -f "$guidance_file" ]]; then
    echo "# ${agent} — Personal Guidance" > "$guidance_file"
    echo "*Updated by Synapse auto-promotion.*" >> "$guidance_file"
    echo "" >> "$guidance_file"
    echo "## Active Guidance" >> "$guidance_file"
    echo "| Key | Rule |" >> "$guidance_file"
    echo "|---|---|" >> "$guidance_file"
    echo "" >> "$guidance_file"
    echo "## Promotion History" >> "$guidance_file"
    echo "| Date | Key | Reason |" >> "$guidance_file"
    echo "|---|---|---|" >> "$guidance_file"
  fi
  
  # Check if key already exists (avoid duplicate)
  if grep -q "| $key |" "$guidance_file" 2>/dev/null; then
    log "  SKIP: ${key} already exists in ${agent}.md"
    continue
  fi
  
  # Append to Active Guidance table
  sed -i '' "/|---|---.*|$/a | $key | $rule |" "$guidance_file"
  
  # Append to Promotion History
  sed -i '' "/|---|---|---.*|$/a | ${open_date} | $key | auto-promoted from synthesis |" "$guidance_file"
  
  log "  ✓ ${key} → ${agent}.md"
  PROMOTED_COUNT=$((PROMOTED_COUNT + 1))
done

[[ $PROMOTED_COUNT -gt 0 ]] && log "Auto-promoted: ${PROMOTED_COUNT} entries" || log "No auto-promotions this run"

# ============================================================
# Step 8: Contradiction log + notification
# ============================================================
log_section "STEP 8: Contradiction log"

CONTRADICTION_LOG="${SYNAPSE}/contradiction-log.md"
[[ ! -f "$CONTRADICTION_LOG" ]] && echo "# Contradiction Log" > "$CONTRADICTION_LOG" && echo "" >> "$CONTRADICTION_LOG"

# Find tier-2 entries with contradictions
CONTRADICTION_OPENED=false
for entry_data in "${NEW_ENTRIES[@]}"; do
  block=$(echo "$entry_data" | cut -d'|' -f3-)
  
  if echo "$block" | grep -qi "mistake\|wrong\|failed\|bug\|broke\|error\|correction\|verify\|test\|confirmed\|reproduced"; then
    entry_id=$(echo "$entry_data" | cut -d'|' -f1)
    agent=$(echo "$entry_id" | cut -d':' -f1)
    open_date=$(echo "$entry_id" | cut -d':' -f2)
    hhmm=$(echo "$entry_id" | cut -d':' -f4)
    
    # Extract what-broke for contradiction detail
    what_broke=$(echo "$block" | grep -A1 "### What broke or surprised me?" | tail -n1 | sed 's/^[[:space:]]*//')
    
    # Check if contradiction already open for this agent + pattern
    already_open=false
    if [[ -s "$CONTRADICTION_LOG" ]]; then
      pattern_key=$(echo "$what_broke" | tr -d '.,!?' | tr -s ' ' | cut -c1-40 | tr ' ' '-')
      if grep -q "## Contradiction.*$agent" "$CONTRADICTION_LOG" 2>/dev/null && grep -q "$pattern_key" "$CONTRADICTION_LOG" 2>/dev/null; then
        already_open=true
      fi
    fi
    
    if [[ "$already_open" == "false" ]]; then
      # Get existing count
      existing_count=$(grep -c "^## Contradiction" "$CONTRADICTION_LOG" 2>/dev/null || echo "0")
      new_num=$((existing_count + 1))
      
      cat >> "$CONTRADICTION_LOG" << EOF

## Contradiction #${new_num} — ${agent} — ${open_date}
- Existing guidance: (check guidance/${agent}.md)
- Agent stated: "${what_broke}"
- Conflicting evidence: reflection ${open_date} ${hhmm} (tier-2)
- Level 1 met: yes — ${open_date}
- Level 2 met: no — 0/3 confirmations
- Status: OPEN
- review_note: (pending)
- Resolution: (pending)
- Resolved at: (pending)
EOF
      
      CONTRADICTION_OPENED=true
      log "  ⚠ Contradiction #${new_num} opened for ${agent}"
    fi
  fi
done

[[ "$CONTRADICTION_OPENED" == "true" ]] && {
  log "  → Notification sent"
  # Cross-platform notification
  if [[ "$(uname)" == "Darwin" ]]; then
    osascript -e 'display notification "Synapse: contradiction opened. Review: memory/synapse/contradiction-log.md" with title "Synapse Alert"' 2>/dev/null || true
  elif command -v notify-send &>/dev/null; then
    notify-send "Synapse Alert" "Contradiction opened. Review memory/synapse/contradiction-log.md" 2>/dev/null || true
  fi
} || log "  No new contradictions"

# ============================================================
# Step 9: Synthesis narrative
# ============================================================
log_section "STEP 9: Narrative"

NARRATIVE_FILE="${SYNAPSE}/chronicle-reflections/${RUN_DATE}.md"

{
  echo "# Synapse Chronicle — ${RUN_DATE}"
  echo "*Synthesis run: ${TIMESTAMP}*"
  echo ""
  echo "## Processing Summary"
  echo "- Entries processed: ${#NEW_ENTRIES[@]}"
  echo "- Agents: ${!AGENT_COUNTS[*]}"
  echo "- Auto-promoted: ${PROMOTED_COUNT}"
  echo "- Contradictions opened: $([[ "$CONTRADICTION_OPENED" == "true" ]] && echo "yes" || echo "none")"
  echo ""
  echo "## Proposals"
  echo "$PROPOSAL_OUTPUT"
} > "$NARRATIVE_FILE"

log "Written: ${NARRATIVE_FILE}"

# ============================================================
# Step 10: Commit processed IDs
# ============================================================
log_section "STEP 10: Commit"

for entry_data in "${NEW_ENTRIES[@]}"; do
  echo "$(echo "$entry_data" | cut -d'|' -f1)" >> "$PROCESSED_REGISTRY"
done

log "Committed: ${#NEW_ENTRIES[@]} IDs"

# ============================================================
# Step 11: Update file-mtimes.json
# ============================================================
log_section "STEP 11: mtimes"

NEW_MTIMES="{"
first=true
for filepath in "${READ_LIST[@]}"; do
  current_mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "0")
  escaped_path=$(echo "$filepath" | jq -Rs '.' 2>/dev/null || echo "\"$filepath\"")
  [[ "$first" == "true" ]] && first=false || NEW_MTIMES+=","
  NEW_MTIMES+="
  ${escaped_path}: ${current_mtime}"
done
NEW_MTIMES+="
}"

if [[ -s "$FILE_MTIMES" ]]; then
  jq -s '.[0] * .[1]' "$FILE_MTIMES" <(echo "$NEW_MTIMES") > "${FILE_MTIMES}.new" 2>/dev/null && mv "${FILE_MTIMES}.new" "$FILE_MTIMES" || echo "$NEW_MTIMES" > "$FILE_MTIMES"
else
  echo "$NEW_MTIMES" > "$FILE_MTIMES"
fi

log "Updated: ${#READ_LIST[@]} files"

# ============================================================
# Step 12: Checkpoint
# ============================================================
log_section "STEP 12: Checkpoint"

{
  echo "# Checkpoint — ${RUN_DATE}"
  echo "*${TIMESTAMP}*"
  echo ""
  echo "## Metadata"
  echo "- Entries processed: ${#NEW_ENTRIES[@]}"
  echo "- Agents: ${!AGENT_COUNTS[*]}"
  echo "- Auto-promoted: ${PROMOTED_COUNT}"
  echo "- Contradictions opened: $([[ "$CONTRADICTION_OPENED" == "true" ]] && echo "yes" || echo "none")"
  echo ""
  echo "## Outputs"
  echo "- Proposals: ${PROPOSALS_FILE}"
  echo "- Narrative: ${NARRATIVE_FILE}"
  echo "- Registry: +${#NEW_ENTRIES[@]} IDs"
} > "${SYNAPSE}/checkpoint-${RUN_DATE}.md"

# ============================================================
# Complete
# ============================================================
log_section "Synthesis complete — ${RUN_DATE}"
log "Proposals: ${PROPOSALS_FILE}"
log "Auto-promotions: ${PROMOTED_COUNT}"
log "Registry: $(wc -l < "$PROCESSED_REGISTRY") total"

exit 0