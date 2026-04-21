#!/usr/bin/env node
/**
 * Synapse Synthesis Trigger — SessionEnd hook
 * Runs synthesis pipeline after session ends.
 * Checks if enough time has passed (not every session — throttle to avoid spam).
 */
const fs = require('fs');
const path = require('path');
const os = require('os');
const { execSync } = require('child_process');

const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SESSION_LOG = path.join(MEMORY, 'synapse', 'session-log.md');

// Throttle: only run synthesis if last run was > 4 hours ago
const THROTTLE_FILE = path.join(MEMORY, 'synapse', '.last-synthesis');
const THROTTLE_MS = 4 * 60 * 60 * 1000; // 4 hours

function canRunSynthesis() {
  if (!fs.existsSync(THROTTLE_FILE)) return true;
  
  const lastRun = parseInt(fs.readFileSync(THROTTLE_FILE, 'utf8').trim(), 10);
  const now = Date.now();
  
  return (now - lastRun) > THROTTLE_MS;
}

function recordSynthesisRun() {
  fs.writeFileSync(THROTTLE_FILE, Date.now().toString(), 'utf8');
}

function getRecentReflections() {
  const reflectionsDir = path.join(MEMORY, 'reflections', 'claude-code');
  if (!fs.existsSync(reflectionsDir)) return [];
  
  const files = fs.readdirSync(reflectionsDir).filter(f => f.endsWith('.md'));
  if (files.length === 0) return [];
  
  // Get last modified file
  const lastFile = files.sort((a, b) => {
    const aStat = fs.statSync(path.join(reflectionsDir, a));
    const bStat = fs.statSync(path.join(reflectionsDir, b));
    return bStat.mtimeMs - aStat.mtimeMs;
  })[0];
  
  const content = fs.readFileSync(path.join(reflectionsDir, lastFile), 'utf8');
  const matches = content.match(/^## Reflection —/gm);
  return matches ? matches.length : 0;
}

function main() {
  try {
    // Check throttle
    if (!canRunSynthesis()) {
      console.error('[Synapse Synthesis] Throttled — last run < 4h ago. Next run allowed soon.');
      process.exit(0);
    }
    
    // Only run if there are reflections to process
    const reflectionCount = getRecentReflections();
    if (reflectionCount === 0) {
      console.error('[Synapse Synthesis] No reflections to process. Skipping.');
      process.exit(0);
    }
    
    console.error(`[Synapse Synthesis] Triggering — ${reflectionCount} reflections available`);
    
    // Run synthesis in background (don't block SessionEnd)
    const synthesisScript = path.join(SYNAPSE_ROOT, 'scripts', 'synthesis.sh');
    if (fs.existsSync(synthesisScript)) {
      // Run async — we exit immediately and let it run in background
      try {
        execSync(`"${synthesisScript}" >> "${path.join(MEMORY, 'synapse', 'synthesis.log')}" 2>&1 &`, {
          cwd: SYNAPSE_ROOT,
          stdio: 'ignore'
        });
        recordSynthesisRun();
        console.error('[Synapse Synthesis] Pipeline triggered successfully');
      } catch (err) {
        console.error(`[Synapse Synthesis] Trigger failed: ${err.message}`);
      }
    } else {
      console.error('[Synapse Synthesis] Script not found — ensure scripts/synthesis.sh exists');
    }
    
    process.exit(0);
  } catch (err) {
    console.error(`[Synapse Synthesis] Error: ${err.message}`);
    process.exit(0);
  }
}

main();