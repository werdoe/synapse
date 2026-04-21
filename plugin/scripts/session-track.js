#!/usr/bin/env node
/**
 * Synapse Session Track — UserPromptSubmit hook
 * Logs user prompts with session context for pattern analysis.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SYNAPSE_AGENT_NAME = process.env.SYNAPSE_AGENT_NAME || 'claude-code';

let hookInput = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { hookInput += d; });
process.stdin.on('end', () => {
  try {
    const sessionMarkerPath = path.join(MEMORY, 'synapse', '.session-open');
    if (!fs.existsSync(sessionMarkerPath)) {
      process.exit(0);
    }
    
    const marker = JSON.parse(fs.readFileSync(sessionMarkerPath, 'utf8'));
    const openDate = marker.sessionId.slice(0, 10);
    const trackFile = path.join(MEMORY, 'synapse', 'session-track.jsonl');
    
    // Parse user prompt
    let prompt = hookInput.trim();
    if (prompt.length > 200) {
      prompt = prompt.slice(0, 200) + '...';
    }
    
    const entry = JSON.stringify({
      timestamp: new Date().toISOString(),
      sessionId: marker.sessionId,
      agent: SYNAPSE_AGENT_NAME,
      type: 'user-prompt',
      prompt
    });
    
    fs.appendFileSync(trackFile, entry + '\n', 'utf8');
    
    process.exit(0);
  } catch (err) {
    console.error(`[Synapse SessionTrack] ${err.message}`);
    process.exit(0);
  }
});