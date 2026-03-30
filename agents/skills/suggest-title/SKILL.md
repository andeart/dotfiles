---
name: suggest-title
description: Suggest a title for the current conversation based on what's been discussed, then copy it to the clipboard. Use this skill whenever the user asks to "suggest a title", "name this conversation", "what should I call this", "rename this chat", or any variation of wanting a title for the current session. Also trigger when the user says "/suggest-title". Do NOT trigger for naming files, projects, or other artifacts - only for titling the conversation itself.
---

# Suggest Conversation Title

Read the current conversation, distill it into a concise title, copy it to the clipboard, and display it.

## How it works

The conversation is already in context - no file reads needed. Scan it from start to finish to understand:
- What the main topic or task is
- What was actually accomplished or decided (not just what was asked)
- Any pivots or secondary themes worth reflecting

Then write a title, copy it, and show it.

## Writing the title

**Style:** Noun phrase, not a sentence or command. Think of it like a document title or a meeting name - descriptive, not imperative. Capitalize the first word and proper nouns only (sentence case).

Good: `Linear project setup and DX skill creation`
Good: `Smart Home project rename and statusline issue`
Not great: `Setting up Linear projects` (too gerund-heavy)
Not great: `We renamed the project and created some issues` (too verbose/informal)

**Length:** Aim for 4–8 words. Enough to be meaningful, short enough to scan.

**Specificity:** Prefer concrete over vague. "Linear DX project and statusline issue" is better than "Project management tasks". If the conversation covered multiple things, join them with "and" or pick the dominant theme.

**When the conversation changed direction:** Reflect the overall arc, not just the beginning or end. If it started as one thing and became another, find a title that captures both or favors the more significant part.

## Clipboard

After drafting the title, copy the plain text (no markdown, no quotes) to the clipboard:

```bash
echo -n "your title here" | pbcopy
```

## Output

Show the title in a code block so it's easy to read, and confirm it's been copied. Mention that `/rename` can be used to apply it. Keep surrounding commentary brief.
