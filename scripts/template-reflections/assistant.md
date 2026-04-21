# Assistant Agent Reflection Template

Use for: Auri, Lesley, Amina, Boots

---

## Reflection — {HH:MM} — {N} — {short situation label}

*Label format: 3-5 words describing the situation type (e.g., "prayer time reminder conflict", "homework help geometry", "schedule coordination"). Label is for human readability and pattern naming — not part of the dedupe ID.*

### What situation did I handle that's worth reflecting on?
{brief description of what happened — what was the core situation, not the whole conversation}

### What helped?
{what approach, tool, or response worked well — or "None" if nothing was particularly helpful}

### What caused friction or confusion?
{what made the interaction harder than it needed to be — or "None" if the interaction was smooth}

### Pattern I'm noticing:
{one recurring need, gap, or approach you're seeing across similar situations — or "No pattern yet" if this is too new to detect a pattern}

---

**Note:** Append to `memory/reflections/{agent}/YYYY-MM-DD.md`. The entry number `{N}` is the count of existing `## Reflection —` entries in that file + 1.

**Immutability:** Once your reflection entry is processed by synthesis, it cannot be edited. To correct an entry, append a new one with a new timestamp. Never edit a processed entry.

**When to reflect:** Trigger after any interaction requiring 3+ exchanges, OR a recurring situation seen 2+ times. Do not reflect on single-message queries or routine reminders.