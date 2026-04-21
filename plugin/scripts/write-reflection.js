#!/usr/bin/env node
/**
 * Synapse Write Reflection — Stop hook
 * Reads session data and writes the reflection entry.
 * This is the "you done good work" moment — captures what happened.
 */
const fs = require('fs');
const path = require('path');
const os = require('os');

const HOME = os.homedir();
const SYNAPSE_ROOT = process.env.SYNAPSE_ROOT || path.join(HOME, 'synapse');
const MEMORY = process.env.SYNAPSE_MEM || path.join(SYNAPSE_ROOT, 'memory');
const SYNAPSE_AGENT_NAME = process.env.SYNAPSE_AGENT_NAME || 'claude-code';

// Check for env-var pre-set reflection data (from wrapper or CLI)
const SUMMARY = process.env.SYNAPSE_SUMMARY || '';
const BROKE = process.env.SYNAPSE_BROKE || '';
const DIFFERENT = process.env.SYNAPSE_DIFFERENT || '';
const FLAG_FOR = process.env.SYNAPSE_FLAG_FOR || '';

function main() {
  try {
    const sessionMarkerPath = path.join(MEMORY, 'synapse', '.session-open');
    
    if (!fs.existsSync(sessionMarkerPath)) {
      console.error('[Synapse] No session open — cannot write reflection');
      process.exit(0);
    }
    
    const marker = JSON.parse(fs.readFileSync(sessionMarkerPath, 'utf8'));
    const openDate = marker.sessionId.slice(0, 10);
    const sessionId = marker.sessionId;
    const hhmm = sessionId.split('-').slice(1).join('').slice(0, 4);
    
    const reflectionFile = path.join(MEMORY, 'reflections', SYNAPSE_AGENT_NAME, `${openDate}.md`);
    
    // Count existing entries
    let entryCount = 0;
    if (fs.existsSync(reflectionFile)) {
      const content = fs.readFileSync(reflectionFile, 'utf8');
      const matches = content.match(/^## Reflection —/gm);
      entryCount = matches ? matches.length : 0;
    } else {
      // Create file with header
      const dir = path.dirname(reflectionFile);
      fs.mkdirSync(dir, { recursive: true });
      fs.writeFileSync(reflectionFile, `# Synapse Reflections — ${openDate}\n\n`, 'utf8');
    }
    
    const N = entryCount + 1;
    
    // Determine task label from session
    let taskLabel = process.env.SYNAPSE_TASK || 'claude-code session';
    
    // Get session track data for context
    const trackFile = path.join(MEMORY, 'synapse', 'session-track.jsonl');
    let userPromptSummary = '';
    if (fs.existsSync(trackFile)) {
      const lines = fs.readFileSync(trackFile, 'utf8').trim().split('\n').filter(l => l.includes(sessionId));
      if (lines.length > 0) {
        try {
          const lastEntry = JSON.parse(lines[lines.length - 1]);
          userPromptSummary = lastEntry.prompt || '';
          if (userPromptSummary.length > 100) {
            taskLabel = userPromptSummary.slice(0, 80) + '...';
          }
        } catch {}
      }
    }
    
    // Check observations for patterns
    const observationsDir = path.join(MEMORY, 'synapse', 'observations', openDate);
    let observationSummary = '';
    if (fs.existsSync(observationsDir)) {
      const obsFiles = fs.readdirSync(observationsDir);
      const errors = obsFiles.filter(f => {
        const obs = JSON.parse(fs.readFileSync(path.join(observationsDir, f), 'utf8'));
        return obs.summary && obs.summary.includes('error') || obs.summary.includes('failed') || obs.summary.includes('not found');
      });
      if (errors.length > 0) {
        observationSummary = `${errors.length} tool observations with errors`;
      }
    }
    
    // Build reflection entry
    const workSummary = SUMMARY || taskLabel;
    const whatBroke = BROKE || (observationSummary ? observationSummary : 'Nothing unexpected');
    const whatDifferent = DIFFERENT || 'No changes';
    const flagFor = FLAG_FOR || 'None';
    
    const entry = `
## Reflection — ${hhmm} — ${N} — ${taskLabel}

### What did I do?
${workSummary}

### What broke or surprised me?
${whatBroke}

### What would I do differently?
${whatDifferent}

### Does this challenge any of my personal guidance?
No

### Flag for:
${flagFor}
`;
    
    fs.appendFileSync(reflectionFile, entry, 'utf8');
    
    // Update chronicle
    const chroniclePath = path.join(MEMORY, 'chronicles', `${openDate}.md`);
    if (fs.existsSync(chroniclePath)) {
      fs.appendFileSync(chroniclePath, `[${new Date().toISOString()}] Synapse reflection written (#${N}) for session ${sessionId}\n`, 'utf8');
    }
    
    // Clean up session marker
    fs.unlinkSync(sessionMarkerPath);
    
    console.error(`[Synapse] Reflection #${N} written for ${sessionId}`);
    
    process.exit(0);
  } catch (err) {
    console.error(`[Synapse WriteReflection] Error: ${err.message}`);
    process.exit(0);
  }
}

main();