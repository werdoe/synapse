#!/usr/bin/env node
/**
 * Synapse Init Script
 * Runs on Setup hook — initializes memory directory structure
 * and verifies the plugin is properly configured.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

// Determine paths
const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SYNAPSE_AGENT_NAME = process.env.SYNAPSE_AGENT_NAME || 'claude-code';

function log(msg) {
  console.error(`[Synapse Init] ${msg}`);
}

function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
    log(`Created: ${dir}`);
  }
}

function ensureFile(filepath, content = '') {
  if (!fs.existsSync(filepath)) {
    fs.writeFileSync(filepath, content, 'utf8');
    log(`Created: ${filepath}`);
  }
}

try {
  // Ensure directory structure
  ensureDir(MEMORY);
  ensureDir(path.join(MEMORY, 'guidance'));
  ensureDir(path.join(MEMORY, 'reflections', SYNAPSE_AGENT_NAME));
  ensureDir(path.join(MEMORY, 'chronicles'));
  ensureDir(path.join(MEMORY, 'synapse', 'proposals'));
  ensureDir(path.join(MEMORY, 'synapse', 'chronicle-reflections'));

  // Ensure runtime files
  const sessionLog = path.join(MEMORY, 'synapse', 'session-log.md');
  if (!fs.existsSync(sessionLog)) {
    fs.writeFileSync(sessionLog, '# Synapse Session Log\n\n', 'utf8');
  }

  const registry = path.join(MEMORY, 'synapse', 'processed-registry.jsonl');
  ensureFile(registry, '');

  const fileMtimes = path.join(MEMORY, 'synapse', 'file-mtimes.json');
  ensureFile(fileMtimes, '{}');

  const contradictionLog = path.join(MEMORY, 'synapse', 'contradiction-log.md');
  ensureFile(contradictionLog, '# Contradiction Log\n\n');

  // Ensure personal guidance file exists
  const personalGuidance = path.join(MEMORY, 'guidance', `${SYNAPSE_AGENT_NAME}.md`);
  if (!fs.existsSync(personalGuidance)) {
    fs.writeFileSync(personalGuidance, `# ${SYNAPSE_AGENT_NAME} — Personal Guidance
*Updated by Synapse auto-promotion and manual review.*

## Active Guidance
| Key | Rule |
|---|---|
`, 'utf8');
    log(`Created personal guidance: ${personalGuidance}`);
  }

  // Ensure shared guidance file exists
  const sharedGuidance = path.join(MEMORY, 'guidance', 'shared.md');
  if (!fs.existsSync(sharedGuidance)) {
    fs.writeFileSync(sharedGuidance, `# Shared Fleet Guidance
*Two valid promotion paths: (1) normal — 2+ agents independently confirmed;
(2) exception — manual orchestrator with tier-1 chronicle evidence.*

## Active Guidance
| Key | Rule | Path | Confirmed By | Evidence | Date |
|---|---|---|---|---|---|
`, 'utf8');
    log(`Created shared guidance: ${sharedGuidance}`);
  }

  // Write checkpoint
  const today = new Date().toISOString().slice(0, 10);
  const checkpoint = path.join(MEMORY, 'synapse', `checkpoint-${today}.md`);
  fs.writeFileSync(checkpoint, `# Checkpoint — ${today}\n*Init complete*\n\n## Status\n- Memory initialized\n- Guidance files ready\n`, 'utf8');

  log('Synapse initialized successfully');
  process.exit(0);
} catch (err) {
  log(`ERROR: ${err.message}`);
  process.exit(0); // Exit 0 to not block setup
}