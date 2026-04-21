#!/usr/bin/env node
/**
 * Synapse Guidance Injection
 * Runs on SessionStart hook — reads Synapse guidance and injects it
 * into the Claude Code session context.
 * 
 * This is the critical piece: guidance lives on disk and gets injected
 * into every Claude Code session so the agent actually reads it.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SYNAPSE_AGENT_NAME = process.env.SYNAPSE_AGENT_NAME || 'claude-code';

// Inject via environment file that Claude Code reads at startup
const INJECT_FILE = path.join(SYNAPSE_ROOT, '.synapse-inject.md');
const SESSION_MARKER = path.join(MEMORY, 'synapse', '.session-open');

function getGuidance() {
  const personalPath = path.join(MEMORY, 'guidance', `${SYNAPSE_AGENT_NAME}.md`);
  const sharedPath = path.join(MEMORY, 'guidance', 'shared.md');
  
  let output = '';
  
  // Personal guidance
  if (fs.existsSync(personalPath)) {
    const content = fs.readFileSync(personalPath, 'utf8');
    const entries = content.match(/\| P-[^\|]+\|[^\|]+\|/g) || [];
    if (entries.length > 0) {
      output += '## Your Synapse Personal Guidance\n';
      output += entries.slice(-5).map(e => {
        const parts = e.split('|').map(p => p.trim());
        return `- [${parts[0]}] ${parts[1]}`;
      }).join('\n');
      output += '\n\n';
    }
  }
  
  // Shared guidance
  if (fs.existsSync(sharedPath)) {
    const content = fs.readFileSync(sharedPath, 'utf8');
    const entries = content.match(/\| GS-[^\|]+\|[^\|]+\|/g) || [];
    if (entries.length > 0) {
      output += '## Synapse Fleet Guidance (shared patterns)\n';
      output += entries.slice(-5).map(e => {
        const parts = e.split('|').map(p => p.trim());
        return `- [${parts[0]}] ${parts[1]}`;
      }).join('\n');
      output += '\n';
    }
  }
  
  return output;
}

function writeSessionMarker() {
  const now = new Date().toISOString();
  const openDate = now.slice(0, 10);
  const hhmm = now.slice(11, 16).replace(':', '');
  const sessionId = `${openDate}-${hhmm}`;
  
  fs.writeFileSync(SESSION_MARKER, JSON.stringify({
    sessionId,
    openedAt: now,
    agent: SYNAPSE_AGENT_NAME
  }, null, 2), 'utf8');
  
  return sessionId;
}

function main() {
  try {
    const guidance = getGuidance();
    const sessionId = writeSessionMarker();
    
    if (guidance) {
      // Write the injection file — Claude Code can read this via Read tool
      const injectContent = `---
 Synapse Guidance (auto-injected — ${new Date().toISOString().slice(0, 16)})
 Session: ${sessionId}
---
${guidance}
---
Past mistakes to avoid:
${getPastMistakes()}
`;
      fs.writeFileSync(INJECT_FILE, injectContent, 'utf8');
      
      // Print guidance to stdout — this gets shown to the user and
      // can be captured by Claude Code's session context
      if (process.env.SYNAPSE_VERBOSE !== 'false') {
        console.log('\n🧠 Synapse — your active guidance:\n');
        console.log(guidance);
      }
    } else {
      fs.writeFileSync(INJECT_FILE, `# Synapse — no guidance yet\nRun a few sessions to build patterns.\n`, 'utf8');
      console.log('[Synapse] No guidance yet — work a few sessions to build patterns');
    }
    
    process.exit(0);
  } catch (err) {
    console.error(`[Synapse] Guidance injection error: ${err.message}`);
    process.exit(0);
  }
}

function getPastMistakes() {
  // Read reflections and extract "what broke" entries
  const reflectionsDir = path.join(MEMORY, 'reflections', SYNAPSE_AGENT_NAME);
  if (!fs.existsSync(reflectionsDir)) return '  (none yet)';
  
  const files = fs.readdirSync(reflectionsDir).filter(f => f.endsWith('.md')).slice(-7);
  const mistakes = [];
  
  for (const file of files) {
    const content = fs.readFileSync(path.join(reflectionsDir, file), 'utf8');
    const blocks = content.split(/^## Reflection/m);
    for (const block of blocks) {
      const match = block.match(/What broke or surprised me\?[\r\n]+(.+?)(?=\n###|$)/s);
      if (match && match[1] && !match[1].includes('Nothing') && !match[1].includes('nothing')) {
        const text = match[1].trim().slice(0, 80);
        if (text && text !== 'Nothing unexpected') {
          mistakes.push(`  • ${text}`);
        }
      }
    }
  }
  
  return mistakes.length > 0 ? mistakes.slice(-5).join('\n') : '  (none yet — good start!)';
}

main();