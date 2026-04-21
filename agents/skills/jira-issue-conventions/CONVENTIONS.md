# Jira Issue Writing Conventions

Shared writing rules for Anurag's Jira issues. Both the `jira-create-issue` and `jira-refine-issue`
skills Read this file before composing or editing issue content, so every ticket has a consistent
voice and shape regardless of whether it's being created from scratch or refined in place.

See the [Examples](#examples) section at the bottom for a worked example with all three sections.

## Description format

Pass descriptions as markdown (`contentFormat: "markdown"`). Jira renders `### Header`, `---`,
`- ` bullets, and `[ ]` / `[x]` checkbox lines acceptably - checkboxes appear as bullet-style
items rather than interactive task items, but that's a fine trade-off for the simplicity.

ADF is supported by the `createJiraIssue` / `editJiraIssue` MCP tools in principle, but has been
flaky in practice - stringified ADF docs have returned `INVALID_INPUT` with no further detail. If
a caller genuinely needs ADF-only features (mentions, inline cards / Smart Links for issue
references, panels), try ADF first and fall back to markdown if the API rejects the payload.

The `agents/skills/jira-migrate-from-linear/SKILL.md` skill documents the ADF node schemas
(`heading`, `rule`, `taskList`/`taskItem`, `bulletList`, `inlineCard`) for cases where ADF is
required.

## Issue Description Structure

Every issue description uses up to three sections in this fixed order. Sections are separated by
horizontal rules (`---`). Use `###` for section headers.

### 1. Impact (required)

A single bullet point that begins with "This will..." and communicates the benefit of delivering this
issue. The tone is outcome-oriented: describe what the user or household gains, not what the code does.

Rules:
- Exactly one bullet point.
- Always starts with "This will...". For bugs, describe the functional outcome the fix achieves,
  not just that a bug is being fixed.
  - Good: "This will restore reliable presence detection so the away-mode automation triggers consistently"
  - Avoid: "This will fix the presence detection bug"
- Communicates a clear benefit. A "so [reason]" clause is fine but not required as long as the benefit is evident.
- Speaks from the perspective of the people affected ("us", "I", "Bry and me"), not the system.

### 2. Notes (optional)

Additional context, links, constraints, or open questions that don't belong in Impact or AC.
Each bullet is a self-contained thought.

Rules:
- Each bullet is one idea. Keep them independent so they can be reordered or removed without breaking context.
- Do not echo acceptance criteria with different phrasing. If a point is testable and belongs in AC, put it there instead.
- Open questions or decisions that need investigation should be called out explicitly (e.g. "**Open question:** ...").
- References to other issues should use Jira's issue-key syntax (e.g. `ENG-123`), which Jira auto-links in rendered ADF.

### 3. Acceptance criteria (required)

A checkbox list (`- [ ]` per item) of specific, testable conditions that must be true for the issue to
be considered done. Written in declarative present tense. Never use plain bullet points (`-` or `*`)
for acceptance criteria - always use checkboxes.

Rules:
- Each item is a **declarative present-tense statement** describing a condition or behavior (e.g. "A notification is sent..." not "Send a notification" or "We should send a notification").
- Items should be independently verifiable. Avoid compound criteria joined by "and" unless the two parts are truly inseparable.
- Order: core behavior first, then edge cases, then dashboard/notification integration, then testing steps last.
- Testing criteria typically appear at the end and start with "The behavior is tested with...".
- Avoid implementation details. Say *what* must be true, not *how* to make it true. Implementation guidance belongs in Notes.
- For bugs, describe the corrected behavior, not the broken state.

## Title Conventions

- Concise, action-oriented.
- Starts with a verb or noun phrase describing the deliverable.
- Bug titles must start with "Fix " (e.g. "Fix stale data in dashboard card after refreshing").
- Use sentence case.
- Examples: "Alert when the oven runs continuously for over 1 hour", "Set up Ollama on Windows laptop for local AI commands", "Fix away-mode automation not triggering when Wi-Fi presence times out".

## Examples

A complete issue with all three sections. If there are no Notes, omit that section and its
surrounding `---` dividers entirely.

```markdown
### Impact

* This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.

---

### Notes

* Presence detection should use Wi-Fi presence as the primary method for the first version.
* A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
* Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.

---

### Acceptance criteria

- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
