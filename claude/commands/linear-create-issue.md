---
name: linear-create-issue
description: >
  Conventions and formatting rules for writing Linear issues for Anurag.
  Use this skill whenever creating, editing, or reviewing Linear issues. Also trigger when the user
  asks to "make an issue", "create a ticket", "write a task", or describes a feature/bug/improvement
  they want tracked in Linear, even if they don't mention Linear by name. This skill covers issue
  structure, section ordering, sentence style, and acceptance criteria patterns. Use it alongside the
  Linear MCP tools (save_issue, list_issues, etc.).
---

# Linear Issue Conventions

These conventions define how issues are structured and written across all of Anurag's Linear projects.
Follow them whenever creating or editing issues so every ticket has a consistent voice and shape.

## Issue Description Structure

Every issue description uses up to three sections in this fixed order. Sections are separated by
horizontal rules (`---`). Use `###` for section headers.

### 1. Impact (required)

A single bullet point that begins with "This will..." and communicates the benefit of delivering this
issue. The tone is outcome-oriented: describe what the user or household gains, not what the code does.

```markdown
### Impact

* This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.
```

Another valid example with a simpler structure:

```markdown
### Impact

* This will enable local AI processing for simple Home Assistant commands like turning lights on and off.
```

Rules:
- Exactly one bullet point.
- Starts with "This will...".
- Communicates a clear benefit. A "so [reason]" clause is fine but not required as long as the benefit is evident.
- Speaks from the perspective of the people affected ("us", "I", "Bry and me"), not the system.

### 2. Notes (optional)

Additional context, flavour, links, constraints, or open questions that help someone understand the
issue beyond the Impact and Acceptance Criteria. Each bullet is a self-contained thought.

Notes should **add information that doesn't belong in the other two sections**, such as background
motivation, references to existing patterns, implementation hints, related links, or decisions that
still need investigation. Notes should not restate what the acceptance criteria already cover in
different words.

```markdown
### Notes

* Presence detection should use Wi-Fi presence as the primary method for the first version.
* A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
* Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.
```

Rules:
- Each bullet is one idea. Keep them independent so they can be reordered or removed without breaking context.
- Do not echo acceptance criteria with different phrasing. If a point is testable and belongs in AC, put it there instead.
- Open questions or decisions that need investigation should be called out explicitly (e.g. "**Open question:** ...").
- References to other issues should use Linear's Markdown link format.

### 3. Acceptance Criteria (required)

A checkbox list of specific, testable conditions that must be true for the issue to be considered done.
Written in declarative present tense.

```markdown
### Acceptance criteria

- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```

Rules:
- Each item is a **declarative present-tense statement** describing a condition or behavior (e.g. "A notification is sent..." not "Send a notification" or "We should send a notification").
- Items should be independently verifiable. Avoid compound criteria joined by "and" unless the two parts are truly inseparable.
- Order: core behavior first, then edge cases, then dashboard/notification integration, then testing steps last.
- Testing criteria typically appear at the end and start with "The behavior is tested with...".
- Avoid implementation details. Say *what* must be true, not *how* to make it true. Implementation guidance belongs in Notes.

## Title Conventions

- Concise, action-oriented.
- Starts with a verb or noun phrase describing the deliverable.
- Use sentence case.
- Examples: "Alert when the oven runs continuously for over 1 hour", "Set up Ollama on Windows laptop for local AI commands", "Dashboard card for currently watching shows with instant launch".

## Default Field Values

When creating issues unless the user specifies otherwise:
- **Assignee**: anurag.d
- **Project**: Do not set. Leave blank so the issue appears in triage.
- **Priority**: Do not set. Leave blank so the issue appears in triage.

The user will specify the team, or it can be inferred from context (e.g. the project being discussed).

Do not set labels, cycles, or estimates unless the user explicitly provides them. Leave them blank so the issue appears in triage.

## Blocking Relations

When the user mentions blockers or dependencies, set them using the `blockedBy` or `blocks` fields.
Only add blocking relations that the user explicitly requests or that are directly referenced in the
conversation. Do not infer blockers from unrelated issues.

## Formatting Reference

The full Markdown skeleton for a well-formed issue:

```markdown
### Impact

* This will [outcome and benefit].

---

### Notes

* [Context, constraint, or implementation hint.]
* [Another independent thought.]

---

### Acceptance criteria

- [ ] [Declarative present-tense condition.]
- [ ] [Another condition.]
- [ ] The behavior is tested with [test scenario].
```

If there are no Notes, omit that section and its surrounding `---` dividers entirely. The result
would be Impact, then `---`, then Acceptance criteria.
