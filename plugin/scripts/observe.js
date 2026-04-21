#!/usr/bin/env node
/**
 * Synapse Observe — PostToolUse hook
 * Captures what actually happened during tool use.
 * Used to build tier-2 evidence (task artifacts) from real work.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SYNAPSE_AGENT_NAME = process.env.SYNAPSE_AGENT_NAME || 'claude-code';

// Read stdin for tool use info from Claude Code hook
let hookInput = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', d => { hookInput += d; });
process.stdin.on('end', () => {
  try {
    // Parse the hook payload (JSON or text from Claude Code)
    let toolName = '';
    let toolResult = '';
    
    try {
      const parsed = JSON.parse(hookInput);
      toolName = parsed.tool || '';
      toolResult = parsed.result || parsed.output || '';
    } catch {
      // Non-JSON input — try to extract tool name from text
      toolName = hookInput.slice(0, 100);
    }
    
    if (!toolName) {
      process.exit(0); // Nothing to observe
    }
    
    const sessionMarkerPath = path.join(MEMORY, 'synapse', '.session-open');
    if (!fs.existsSync(sessionMarkerPath)) {
      process.exit(0); // No session open
    }
    
    const marker = JSON.parse(fs.readFileSync(sessionMarkerPath, 'utf8'));
    const openDate = marker.sessionId.slice(0, 10);
    const observationsDir = path.join(MEMORY, 'synapse', 'observations', openDate);
    
    fs.mkdirSync(observationsDir, { recursive: true });
    
    // Timestamp for this observation
    const timestamp = new Date().toISOString();
    const obsFile = path.join(observationsDir, `${Date.now()}.json`);
    
    const observation = {
      timestamp,
      sessionId: marker.sessionId,
      agent: SYNAPSE_AGENT_NAME,
      tool: toolName,
      summary: summarizeTool(toolName, toolResult),
      raw: toolResult.slice(0, 500) // Keep first 500 chars for context
    };
    
    fs.writeFileSync(obsFile, JSON.stringify(observation, null, 2), 'utf8');
    
    process.exit(0);
  } catch (err) {
    // Non-blocking — log but don't fail
    console.error(`[Synapse Observe] Error: ${err.message}`);
    process.exit(0);
  }
});

function summarizeTool(toolName, result) {
  const r = (result || '').toLowerCase();
  
  if (toolName === 'Read' || toolName === 'read') {
    if (r.includes('does not exist') || r.includes('no such file')) return 'tried to read missing file';
    if (r.includes('error')) return 'read encountered error';
    return 'file read successfully';
  }
  
  if (toolName === 'Write' || toolName === 'write') {
    if (r.includes('written') || r.includes('created')) return 'file written/created';
    return 'write operation';
  }
  
  if (toolName === 'Edit' || toolName === 'edit') {
    if (r.includes('edited') || r.includes('applied')) return 'file edited successfully';
    return 'edit operation';
  }
  
  if (toolName === 'Bash' || toolName === 'exec' || toolName === 'run') {
    if (r.includes('error') || r.includes('failed')) return 'shell command failed';
    if (r.includes('not found') || r.includes('command not found')) return 'command not found';
    if (r.includes('permission denied')) return 'permission denied';
    return 'shell command succeeded';
  }
  
  if (toolName === 'Search' || toolName === 'grep') {
    if (r.includes('no matches')) return 'no matches found';
    return `search returned results`;
  }
  
  return `used ${toolName}`;
}