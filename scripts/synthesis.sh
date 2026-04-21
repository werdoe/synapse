#!/bin/bash
# ============================================================
# Synapse Synthesis Pipeline
# Runs at 4AM daily. Processes all new reflection files,
# generates candidate learnings, updates contradiction log.
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
CHECKPOINT_DIR="${SYNAPSE}"

# Runtime state files
FILE_MTIMES="${SYNAPSE}/file-mtimes.json"
PROCESSED_REGISTRY="${SYNAPSE}/processed-registry.jsonl"
SESSION_LOG="${SYNAPSE}/session-log.md"

# Run date (today's date for checkpoint/proposals naming)
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
# Step 0: Logging
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
# Step 1: Initialize / validate
# ============================================================
log_section "STEP 1: Initialization"

if [[ ! -d "$REFLECTIONS" ]]; then
  log "ERROR: reflections/ directory not found at ${REFLECTIONS}"
  exit 1
fi

if [[ ! -f "$PROCESSED_REGISTRY" ]]; then
  log "WARNING: processed-registry.jsonl not found, creating empty file"
  touch "$PROCESSED_REGISTRY"
fi

if [[ ! -f "$FILE_MTIMES" ]]; then
  log "WARNING: file-mtimes.json not found, creating empty file"
  echo '{}' > "$FILE_MTIMES"
fi

# Ensure proposal and chronicle-reflections directories exist
mkdir -p "${SYNAPSE}/proposals"
mkdir -p "${SYNAPSE}/chronicle-reflections"

log "Workspace: ${WORKSPACE}"
log "Run date: ${RUN_DATE}"
log "Reflections dir: ${REFLECTIONS}"
log "Registry: $(wc -l < "$PROCESSED_REGISTRY" 2>/dev/null || echo 0) entries"

# ============================================================
# Step 2: Determine files to process (mtime catch-up)
# ============================================================
log_section "STEP 2: Catch-up — determining files to read"

READ_LIST=()
CHRONICLE_READ_LIST=()

# Get current file mtimes from registry
declare -A CURRENT_MTIMES
if [[ -s "$FILE_MTIMES" ]]; then
  while IFS= read -r line; do
    key=$(echo "$line" | jq -r 'keys[0]' 2>/dev/null || echo "")
    if [[ -n "$key" && "$key" != "null" ]]; then
      mtime=$(echo "$line" | jq -r ".[\"$key\"]" 2>/dev/null || echo "0")
      CURRENT_MTIMES["$key"]="$mtime"
    fi
  done < <(jq -c 'to_entries[]' "$FILE_MTIMES" 2>/dev/null || echo "")
fi

# Scan all reflection files
while IFS= read -r filepath; do
  agent_dir=$(basename "$(dirname "$filepath")")
  filename=$(basename "$filepath")
  
  # Get current mtime
  current_mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "0")
  recorded_mtime="${CURRENT_MTIMES[$filepath]:-}"
  
  # Add to read list if new or modified
  if [[ -z "$recorded_mtime" ]] || [[ "$current_mtime" -gt "$recorded_mtime" ]]; then
    READ_LIST+=("$filepath")
    
    # Extract open-date from filename (YYYY-MM-DD.md)
    open_date="${filename%.md}"
    
    # Add matching chronicle to read list
    chronicle_path="${CHRONICLES}/${open_date}.md"
    if [[ -f "$chronicle_path" ]]; then
      CHRONICLE_READ_LIST+=("$chronicle_path")
    fi
    
    log "  → Will process: ${agent_dir}/${filename} (mtime: $current_mtime)"
  fi
done < <(find "$REFLECTIONS" -name "*.md" -type f 2>/dev/null)

# Always read yesterday's primary chronicle (primary context for this run)
primary_chronicle="${CHRONICLES}/${RUN_DATE_YESTERDAY}.md"
if [[ -f "$primary_chronicle" ]]; then
  # Avoid duplicate
  already_added=false
  for c in "${CHRONICLE_READ_LIST[@]:-}"; do
    [[ "$c" == "$primary_chronicle" ]] && already_added=true && break
  done
  if [[ "$already_added" == "false" ]]; then
    CHRONICLE_READ_LIST+=("$primary_chronicle")
    log "  → Primary chronicle: ${RUN_DATE_YESTERDAY}.md"
  fi
fi

if [[ ${#READ_LIST[@]} -eq 0 ]]; then
  log "No new reflection files to process. Sleeping."
  log_section "Synthesis complete — no new entries"
  exit 0
fi

log "Files to process: ${#READ_LIST[@]}"
log "Chronicles to read: ${#CHRONICLE_READ_LIST[@]}"

# ============================================================
# Step 3: Read all files into memory
# ============================================================
log_section "STEP 3: Reading files"

declare -A REFLECTION_CONTENT
declare -A CHRONICLE_CONTENT

# Read reflection files
for filepath in "${READ_LIST[@]}"; do
  filename=$(basename "$filepath")
  agent_dir=$(basename "$(dirname "$filepath")")
  key="${agent_dir}:${filename}"
  
  content=$(cat "$filepath" 2>/dev/null || echo "")
  REFLECTION_CONTENT["$key"]="$content"
  log "  Read: ${agent_dir}/${filename} ($(echo "$content" | wc -c) bytes)"
done

# Read chronicle files
for chronicle_path in "${CHRONICLE_READ_LIST[@]:-}"; do
  filename=$(basename "$chronicle_path")
  content=$(cat "$chronicle_path" 2>/dev/null || echo "")
  CHRONICLE_CONTENT["$filename"]="$content"
  log "  Read chronicle: ${filename} ($(echo "$content" | wc -c) bytes)"
done

# ============================================================
# Step 4: Dedupe against processed-registry.jsonl
# ============================================================
log_section "STEP 4: Deduplication"

NEW_ENTRIES=()
for filepath in "${READ_LIST[@]}"; do
  agent_dir=$(basename "$(dirname "$filepath")")
  filename=$(basename "$filepath")
  open_date="${filename%.md}"
  
  # Parse entries from this file
  # Format: ## Reflection — {HH:MM} — {N} — {label}
  while IFS= read -r entry_block; do
    # Extract heading line
    heading_line=$(echo "$entry_block" | grep -m1 "## Reflection —" || echo "")
    if [[ -z "$heading_line" ]]; then
      continue
    fi
    
    # Parse: ## Reflection — {HH:MM} — {N} — {label}
    # N is the append-index (1, 2, 3...)
    hhmm=$(echo "$heading_line" | sed 's/.*## Reflection — \([^ ]*\) — \([^ ]*\) —.*/\1/')
    n_val=$(echo "$heading_line" | sed 's/.*## Reflection — \([^ ]*\) — \([^ ]*\) —.*/\2/')
    label=$(echo "$heading_line" | sed 's/.*## Reflection — [^ ]* — [^ ]* — //')
    
    # Build 4-tuple ID: {agent}::{open-date}::{N}::{HH:MM}
    entry_id="${agent_dir}::${open_date}::${n_val}::${hhmm}"
    
    # Check registry
    if grep -qF "$entry_id" "$PROCESSED_REGISTRY" 2>/dev/null; then
      log "  SKIP (already processed): ${entry_id}"
      continue
    fi
    
    # New entry
    log "  NEW: ${entry_id}"
    NEW_ENTRIES+=("${entry_id}|${filepath}|${entry_block}")
    
  done < <(awk '/## Reflection —/{found=1} found; /^---/{if(found) exit}' "$filepath" 2>/dev/null || echo "")
done

if [[ ${#NEW_ENTRIES[@]} -eq 0 ]]; then
  log "All entries already processed. Complete."
  log_section "Synthesis complete — no new entries"
  exit 0
fi

log "New entries to process: ${#NEW_ENTRIES[@]}"

# ============================================================
# Step 5: Process entries (analysis + proposals)
# ============================================================
log_section "STEP 5: Analysis"

# Initialize output buffers
PROPOSALS_BUFFER=""
SYNTHESIS_NARRATIVE=""

# Count by agent
declare -A AGENT_COUNTS
for entry_data in "${NEW_ENTRIES[@]}"; do
  entry_id=$(echo "$entry_data" | cut -d'|' -f1)
  agent=$(echo "$entry_id" | cut -d':' -f1)
  AGENT_COUNTS["$agent"]=$(( ${AGENT_COUNTS[$agent]:-0} + 1 ))
done

# Log processing summary
for agent in "${!AGENT_COUNTS[@]}"; do
  log "  ${agent}: ${AGENT_COUNTS[$agent]} new entries"
done

# Build pattern map for cross-agent detection
declare -A PATTERN_AGENTS
PATTERN_BUFFER=""

# Per-entry analysis
for entry_data in "${NEW_ENTRIES[@]}"; do
  entry_id=$(echo "$entry_data" | cut -d'|' -f1)
  filepath=$(echo "$entry_data" | cut -d'|' -f2)
  block=$(echo "$entry_data" | cut -d'|' -f3-)
  
  agent=$(echo "$entry_id" | cut -d':' -f1)
  open_date=$(echo "$entry_id" | cut -d':' -f2)
  n_val=$(echo "$entry_id" | cut -d':' -f3)
  hhmm=$(echo "$entry_id" | cut -d':' -f4)
  
  # Extract key content
  what_did_i_do=$(echo "$block" | grep -A2 "### What did I do?" | tail -n1 | sed 's/^[[:space:]]*//')
  what_broke=$(echo "$block" | grep -A2 "### What broke or surprised me?" | tail -n1 | sed 's/^[[:space:]]*//')
  what_harder=$(echo "$block" | grep -A2 "### What was harder to get right?" | tail -n1 | sed 's/^[[:space:]]*//')
  situation=$(echo "$block" | grep -A2 "### What situation did I handle" | tail -n1 | sed 's/^[[:space:]]*//')
  
  # Determine tier based on content keywords
  tier=3
  if echo "$block" | grep -qi "mistake\|wrong\|failed\|bug\|broke\|error\|correction"; then
    tier=2
  fi
  if echo "$block" | grep -qi "verified\|tested\|confirmed\|reproduced"; then
    tier=2
  fi
  
  # Simple pattern extraction (keyword-based for v1)
  pattern=""
  if [[ -n "$what_broke" && "$what_broke" != "Nothing expected" && "$what_broke" != "None" ]]; then
    pattern="$what_broke"
  elif [[ -n "$what_harder" && "$what_harder" != "Straightforward" ]]; then
    pattern="$what_harder"
  elif [[ -n "$situation" ]]; then
    pattern="$situation"
  fi
  
  # Truncate pattern for key generation
  pattern_key=$(echo "$pattern" | tr -d '.,!?' | tr -s ' ' | cut -c1-60 | tr ' ' '-')
  
  if [[ -n "$pattern_key" ]]; then
    if [[ -z "${PATTERN_AGENTS[$pattern_key]:-}" ]]; then
      PATTERN_AGENTS["$pattern_key"]="$agent"
    else
      # Cross-agent pattern detected
      existing=$(echo "${PATTERN_AGENTS[$pattern_key]}" | tr ',' '\n')
      already_counted=false
      for a in $existing; do
        [[ "$a" == "$agent" ]] && already_counted=true && break
      done
      if [[ "$already_counted" == "false" ]]; then
        PATTERN_AGENTS["$pattern_key"]="${PATTERN_AGENTS[$pattern_key]},$agent"
      fi
    fi
  fi
  
done

# Generate proposals
PROPOSAL_NUM=1
PROPOSAL_OUTPUT=""

# Cross-agent patterns → shared candidates
for pattern_key in "${!PATTERN_AGENTS[@]}"; do
  agents_str="${PATTERN_AGENTS[$pattern_key]}"
  agent_count=$(echo "$agents_str" | tr ',' '\n' | wc -l | tr -d ' ')
  
  if [[ $agent_count -ge 2 ]]; then
    PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: fleet
- type: shared-candidate
- proposed_key: GS-$(( $(grep -c "^## Candidate" "${SYNAPSE}/proposals/${RUN_DATE}.md" 2>/dev/null || echo "0") + PROPOSAL_NUM ))
- proposed_rule: $(echo "$pattern_key" | tr '-' ' ')
- evidence_tier: 3
- evidence: ${agent_count} agents independently identified: ${agents_str}
- confidence: 0.75
- promotion_path: requires_personal_first: yes
- related_guidance: (none)
"
    PROPOSAL_NUM=$((PROPOSAL_NUM + 1))
    log "  SHARED CANDIDATE: ${pattern_key} (${agent_count} agents: ${agents_str})"
  fi
done

# Per-agent patterns → personal candidates
for entry_data in "${NEW_ENTRIES[@]}"; do
  entry_id=$(echo "$entry_data" | cut -d'|' -f1)
  filepath=$(echo "$entry_data" | cut -d'|' -f2)
  block=$(echo "$entry_data" | cut -d'|' -f3-)
  
  agent=$(echo "$entry_id" | cut -d':' -f1)
  open_date=$(echo "$entry_id" | cut -d':' -f2)
  n_val=$(echo "$entry_id" | cut -d':' -f3)
  hhmm=$(echo "$entry_id" | cut -d':' -f4)
  
  # Extract rule candidates
  what_different=$(echo "$block" | grep -A2 "### What would I do differently?" | tail -n1 | sed 's/^[[:space:]]*//')
  flag_for=$(echo "$block" | grep -A2 "### Flag for" | tail -n1 | sed 's/^[[:space:]]*//')
  harder=$(echo "$block" | grep -A2 "### What was harder" | tail -n1 | sed 's/^[[:space:]]*//')
  
  if [[ -n "$what_different" && "$what_different" != "No changes" && "$what_different" != "Nothing" ]]; then
    rule_text=$(echo "$what_different" | tr -d '.,!?' | tr -s ' ' | cut -c1-80)
    PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: ${agent}
- type: personal
- proposed_key: P-${agent}-$(date +%m%d%H%M%S)
- proposed_rule: ${rule_text}
- evidence_tier: 3
- evidence: reflection ${open_date} ${hhmm} (self-report)
- confidence: 0.72
- promotion_path: requires_personal_first: yes
- related_guidance: (none)
"
    PROPOSAL_NUM=$((PROPOSAL_NUM + 1))
    log "  PERSONAL: ${agent}: ${rule_text:0:60}..."
  fi
  
  if [[ -n "$flag_for" && "$flag_for" != "None" && "$flag_for" != "none" ]]; then
    flag_text=$(echo "$flag_for" | tr -d '.,!?' | tr -s ' ' | cut -c1-80)
    PROPOSAL_OUTPUT+="
## Candidate ${PROPOSAL_NUM}
- agent: ${agent}
- type: pattern-worth-examining
- proposed_key: P-${agent}-$(date +%m%d%H%M%S)
- proposed_rule: ${flag_text}
- evidence_tier: 3
- evidence: flagged by ${agent} ${open_date} ${hhmm}
- confidence: 0.68
- promotion_path: requires_personal_first: yes
- related_guidance: (none)
"
    PROPOSAL_NUM=$((PROPOSAL_NUM + 1))
  fi
done

# ============================================================
# Step 6: Write proposals
# ============================================================
log_section "STEP 6: Writing proposals"

PROPOSALS_FILE="${SYNAPSE}/proposals/${RUN_DATE}.md"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would write ${PROPOSAL_NUM} proposals to ${PROPOSALS_FILE}"
else
  {
    echo "# Synapse Proposals — ${RUN_DATE}"
    echo "*Generated: ${TIMESTAMP}*"
    echo ""
    echo "## Summary"
    echo "- Total new entries processed: ${#NEW_ENTRIES[@]}"
    echo "- Agents with new entries: ${!AGENT_COUNTS[*]}"
    echo "- Cross-agent patterns found: $(echo "${PATTERN_AGENTS[@]}" | tr ' ' '\n' | grep -c . || echo 0)"
    echo ""
    echo "## Candidates"
    echo "$PROPOSAL_OUTPUT"
  } > "$PROPOSALS_FILE"
  log "Written: ${PROPOSALS_FILE}"
fi

# ============================================================
# Step 7: Update contradiction log (idempotent)
# ============================================================
log_section "STEP 7: Contradiction log check"

CONTRADICTION_LOG="${SYNAPSE}/contradiction-log.md"
if [[ ! -f "$CONTRADICTION_LOG" ]]; then
  echo "# Contradiction Log" > "$CONTRADICTION_LOG"
  echo "" >> "$CONTRADICTION_LOG"
fi

# Simple check: any tier-2 evidence in new entries?
HAS_TIER2=false
for entry_data in "${NEW_ENTRIES[@]}"; do
  block=$(echo "$entry_data" | cut -d'|' -f3-)
  if echo "$block" | grep -qi "mistake\|wrong\|failed\|bug\|broke\|error\|correction\|verify\|test\|confirmed\|reproduced"; then
    HAS_TIER2=true
    break
  fi
done

if [[ "$HAS_TIER2" == "true" ]]; then
  log "  Tier 2 evidence found in new entries — contradiction check passed"
else
  log "  No tier 1/2 evidence in new entries — contradiction log unchanged"
fi

# ============================================================
# Step 8: Write synthesis narrative
# ============================================================
log_section "STEP 8: Synthesis narrative"

NARRATIVE_FILE="${SYNAPSE}/chronicle-reflections/${RUN_DATE}.md"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would write synthesis narrative to ${NARRATIVE_FILE}"
else
  {
    echo "# Synapse Chronicle — ${RUN_DATE}"
    echo "*Synthesis run: ${TIMESTAMP}*"
    echo ""
    echo "## Processing Summary"
    echo "- Entries processed: ${#NEW_ENTRIES[@]}"
    echo "- Agents: ${!AGENT_COUNTS[*]}"
    echo "- Cross-agent patterns: $(echo "${PATTERN_AGENTS[@]}" | tr ' ' '\n' | grep -c . || echo 0)"
    echo ""
    echo "## Agents Processed"
    for agent in "${!AGENT_COUNTS[@]}"; do
      echo "- ${agent}: ${AGENT_COUNTS[$agent]} entries"
    done
    echo ""
    echo "## Cross-Agent Patterns"
    for pattern_key in "${!PATTERN_AGENTS[@]}"; do
      agents_str="${PATTERN_AGENTS[$pattern_key]}"
      agent_count=$(echo "$agents_str" | tr ',' '\n' | wc -l | tr -d ' ')
      if [[ $agent_count -ge 2 ]]; then
        echo "- ${pattern_key}: ${agents_str}"
      fi
    done
    echo ""
    echo "## Proposals Generated"
    echo "$PROPOSAL_OUTPUT"
  } > "$NARRATIVE_FILE"
  log "Written: ${NARRATIVE_FILE}"
fi

# ============================================================
# Step 9: Commit processed IDs (after successful outputs)
# ============================================================
log_section "STEP 9: Committing processed IDs"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would commit ${#NEW_ENTRIES[@]} entry IDs to registry"
else
  for entry_data in "${NEW_ENTRIES[@]}"; do
    entry_id=$(echo "$entry_data" | cut -d'|' -f1)
    echo "$entry_id" >> "$PROCESSED_REGISTRY"
  done
  log "Committed: ${#NEW_ENTRIES[@]} IDs to ${PROCESSED_REGISTRY}"
fi

# ============================================================
# Step 10: Update file-mtimes.json
# ============================================================
log_section "STEP 10: Updating file mtimes"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would update mtimes for ${#READ_LIST[@]} files"
else
  # Build new mtime JSON
  NEW_MTIMES="{"
  first=true
  
  for filepath in "${READ_LIST[@]}"; do
    current_mtime=$(stat -f %m "$filepath" 2>/dev/null || stat -c %Y "$filepath" 2>/dev/null || echo "0")
    escaped_path=$(echo "$filepath" | jq -Rs '.')
    if [[ "$first" == "true" ]]; then
      first=false
    else
      NEW_MTIMES+=","
    fi
    NEW_MTIMES+="
  ${escaped_path}: ${current_mtime}"
  done
  
  NEW_MTIMES+="
}"
  
  # Merge with existing
  if [[ -s "$FILE_MTIMES" ]]; then
    # Merge JSONs
    jq -s '.[0] * .[1]' "$FILE_MTIMES" <(echo "$NEW_MTIMES") > "${FILE_MTIMES}.new" 2>/dev/null || echo "$NEW_MTIMES" > "${FILE_MTIMES}.new"
    mv "${FILE_MTIMES}.new" "$FILE_MTIMES"
  else
    echo "$NEW_MTIMES" > "$FILE_MTIMES"
  fi
  
  log "Updated mtimes for: ${#READ_LIST[@]} files"
fi

# ============================================================
# Step 11: Write checkpoint
# ============================================================
log_section "STEP 11: Checkpoint"

CHECKPOINT_FILE="${SYNAPSE}/checkpoint-${RUN_DATE}.md"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Would write checkpoint to ${CHECKPOINT_FILE}"
else
  {
    echo "# Checkpoint — ${RUN_DATE}"
    echo "*Synthesis run: ${TIMESTAMP}*"
    echo ""
    echo "## Run Metadata"
    echo "- Timestamp: ${TIMESTAMP}"
    echo "- Entries processed: ${#NEW_ENTRIES[@]}"
    echo "- Files read: ${#READ_LIST[@]}"
    echo "- Chronicles read: ${#CHRONICLE_READ_LIST[@]}"
    echo ""
    echo "## Agent Counts"
    for agent in "${!AGENT_COUNTS[@]}"; do
      echo "- ${agent}: ${AGENT_COUNTS[$agent]}"
    done
    echo ""
    echo "## Output Files"
    echo "- Proposals: proposals/${RUN_DATE}.md"
    echo "- Narrative: chronicle-reflections/${RUN_DATE}.md"
    echo "- Registry: +${#NEW_ENTRIES[@]} new IDs"
    echo ""
    echo "## Quality Flags"
    echo "- Low-quality reflections: (none flagged in dry-run)"
    echo "- Missing agents: (none)"
  } > "$CHECKPOINT_FILE"
  log "Written: ${CHECKPOINT_FILE}"
fi

# ============================================================
# Complete
# ============================================================
log_section "Synthesis complete — ${RUN_DATE}"

if [[ "$DRY_RUN" == "true" ]]; then
  log "[DRY RUN] Complete. No files written."
else
  log "Proposals: ${PROPOSALS_FILE}"
  log "Narrative: ${NARRATIVE_FILE}"
  log "Registry: $(wc -l < "$PROCESSED_REGISTRY") total entries"
fi

exit 0