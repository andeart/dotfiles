---
name: linear-create-issue
description: >
  Conventions and formatting rules for writing Linear issues for Anurag.
  Use this skill whenever creating, editing, or reviewing Linear issues. Also trigger when the user
  asks to "make an issue", "create a ticket", "write a task", "log a bug", "file a bug",
  "report a problem", or describes a feature/bug/improvement they want tracked in Linear, even if
  they don't mention Linear by name. This skill covers issue
  structure, section ordering, sentence style, and acceptance criteria patterns. Use it alongside the
  Linear MCP tools (save_issue, list_issues, etc.).
---

# Linear Create Issue

These conventions define how issues are structured and written across all of Anurag's Linear projects.
Follow them whenever creating or editing issues so every ticket has a consistent voice and shape.

See [examples.md](examples.md) for worked examples of each section and a full skeleton.

## Repo-level defaults (.linear.yml)

Before creating an issue, check for a `.linear.yml` file in the repo root. This file defines default
field values for issues created from this repo.

Supported keys:

| Key | Description | Example |
|-----|-------------|---------|
| `mode` | `mcp` (default) or `manual` | `manual` |
| `project` | Linear project name | `DX` |
| `assignee` | Linear username | `anurag.d` |
| `state` | Initial issue state | `In Progress` |
| `estimate` | Story point estimate | `3` |
| `priority` | Issue priority (0-4) | `3` |

When a key is present in `.linear.yml`, apply it automatically without asking. When a key is absent,
ask the user to choose a value before creating the issue (unless the "Default Field Values" section
below specifies a different fallback). User-provided values always override `.linear.yml` defaults.

### Missing .linear.yml

If no `.linear.yml` exists in the repo root, offer to create one before proceeding. Ask the user for
confirmation first. If they accept, create the file with all supported keys commented out so they can
uncomment and set values as needed:

```yaml
# mode: mcp
# project: 
# assignee: 
# state: 
# estimate: 
# priority: 
```

### Missing keys in existing .linear.yml

After reading an existing `.linear.yml`, if any supported keys are absent, offer to append them in
commented form. This makes it easy for the user to uncomment and set values later rather than looking
up property names. Ask for confirmation before modifying the file.

## Mode

The `mode` key in `.linear.yml` (or a user-provided override) controls how the issue is delivered.
If no mode is configured, default to `mcp`.

| Mode | Behavior |
|------|----------|
| `mcp` | Create the issue directly via Linear MCP tools (`save_issue`, etc.). This is the current default. |
| `manual` | Do not call Linear MCP tools. Instead, output the fully composed issue (title, description, and field values) as Markdown in the response so the user can copy-paste it into Linear. |

### Manual mode output format

When `mode` is `manual`, present the issue in this format:

```
**Title:** <issue title>

**Fields**
- Team: <team>
- Assignee: <assignee>
- Project: <project, or "none">
- Priority: <priority, or "none">
- Estimate: <estimate, or "none">
- State: <state, or "none">

**Description**

<full issue description markdown, exactly as it would be sent to Linear>
```

All other rules in this skill (title conventions, section structure, acceptance criteria style, etc.)
apply identically regardless of mode.

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
- References to other issues should use Linear's Markdown link format.

### 3. Acceptance criteria (required)

A checkbox list of specific, testable conditions that must be true for the issue to be considered done.
Written in declarative present tense.

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

## Default Field Values

When creating issues unless the user specifies otherwise and no `.linear.yml` config is present:
- **Assignee**: anurag.d
- **Project**: Do not set. Leave blank so the issue appears in triage.
- **Priority**: Do not set. Leave blank so the issue appears in triage.

The user will specify the team, or it can be inferred from context (e.g. the project being discussed). If the team cannot be confidently inferred, ask the user.

Do not set labels, cycles, or estimates unless the user explicitly provides them or they come from
`.linear.yml`. Leave them blank so the issue appears in triage.

## Blocking Relations

Only set `blockedBy` or `blocks` when the user explicitly requests it or references a dependency in the conversation.
