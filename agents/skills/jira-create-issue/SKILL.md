---
name: jira-create-issue
description: >
  Conventions and formatting rules for writing Jira issues for Anurag.
  Use this skill whenever creating, editing, or reviewing Jira issues. Also trigger when the user
  asks to "make an issue", "create a ticket", "write a task", "log a bug", "file a bug",
  "report a problem", or describes a feature/bug/improvement they want tracked in Jira, even if
  they don't mention Jira by name. This skill covers issue structure, section ordering, sentence
  style, and acceptance criteria patterns. Use it alongside the Atlassian MCP tools
  (createJiraIssue, searchJiraIssuesUsingJql, transitionJiraIssue, etc.).
---

# Jira Create Issue

These conventions define how issues are structured and written across all of Anurag's Jira spaces.
Follow them whenever creating or editing issues so every ticket has a consistent voice and shape.

See the [Examples](#examples) section at the bottom for a worked example with all three sections.

> **Terminology note.** Atlassian renamed Jira "projects" to "spaces" in the Cloud UI during the
> late-2025 rollout, but the REST API and MCP tools still use "project" (e.g. `projectKey`,
> `getVisibleJiraProjects`). This skill uses "space" everywhere it's user-facing (in `.jira.yml`,
> manual-mode output, and conversation), and translates to `project`/`projectKey` only when calling
> the Atlassian MCP tools.

## Repo-level defaults (.jira.yml)

Before creating an issue, check for a `.jira.yml` file in the repo root. This file defines default
field values for issues created from this repo.

Supported keys:

| Key | Description | Example |
|-----|-------------|---------|
| `mode` | `mcp` (default) or `manual` | `manual` |
| `space` | Jira space name or key (translated to `projectKey` when calling the API) | `ENG` |
| `assignee` | Jira account email or display name (resolved via `lookupJiraAccountId`) | `anurag.devanapally@gmail.com` |
| `state` | Initial issue state: `To Do`, `In Progress`, `Done` | `In Progress` |
| `estimate` | Original estimate. Bare number = hours; also accepts Jira duration strings. | `3` → `3h`, or `1d 4h` |
| `priority` | `Lowest`, `Low`, `Medium`, `High`, `Highest` | `Low` |

State and priority values are accepted case-insensitively but normalized to Jira's native casing
before being sent to the API.

When a key is present in `.jira.yml`, apply it automatically without asking. When a key is absent,
ask the user to choose a value before creating the issue (unless the "Default Field Values" section
below specifies a different fallback). User-provided values always override `.jira.yml` defaults.

### Migrating from an existing .linear.yml

If a `.linear.yml` exists in the repo root (from the pre-Jira era), do not silently ignore it.
Offer to migrate its values into a new `.jira.yml` first:

1. Read the `.linear.yml` values (if any are set).
2. Translate them:
   - `project` → `space`
   - `state`: map `Backlog`/`Todo` → `To Do`, `In Progress` → `In Progress`,
     `Done`/`Canceled`/`Duplicate` → `Done`.
   - `priority`: map `1` (Urgent) → `Highest`, `2` (High) → `High`, `3` (Medium) → `Medium`,
     `4` (Low) → `Low`. Leave `0` (None) unset so the default (`Low`) kicks in.
   - `mode`, `assignee`: copy as-is.
   - `estimate`: leave unset. Linear story points don't convert cleanly to Jira time estimates.
3. Write the translated values to `.jira.yml` (confirm with the user before writing).
4. After `.jira.yml` is created, offer to delete `.linear.yml`. Ask for confirmation explicitly;
   never delete without it.

### Missing .jira.yml

If no `.jira.yml` (and no `.linear.yml`) exists in the repo root, offer to create `.jira.yml`
before proceeding. Ask the user for confirmation first. If they accept, create the file with all
supported keys commented out so they can uncomment and set values as needed:

```yaml
# mode: mcp
# space:
# assignee:
# state:
# estimate:
# priority:
```

### Missing keys in existing .jira.yml

After reading an existing `.jira.yml`, if any supported keys are absent, offer to append them in
commented form. This makes it easy for the user to uncomment and set values later rather than
looking up property names. Ask for confirmation before modifying the file.

## Mode

The `mode` key in `.jira.yml` (or a user-provided override) controls how the issue is delivered.
If no mode is configured, default to `mcp`.

| Mode | Behavior |
|------|----------|
| `mcp` | Create the issue directly via Atlassian MCP tools (`createJiraIssue`, etc.). This is the default. |
| `manual` | Do not call Atlassian MCP tools. Instead, output the fully composed issue (title, description, and field values) as Markdown in the response so the user can copy-paste it into Jira. |

### Manual mode output format

When `mode` is `manual`, present the title and fields as rendered markdown, then wrap the entire
description in a fenced code block so the user can copy-paste it into Jira's editor. Jira's editor
will convert the pasted markdown to ADF on its own - this mode is the safety valve for cases where
direct MCP access isn't available.

Example structure:

    **Title:** <issue title>

    **Fields**
    - Assignee: <assignee>
    - Space: <space, or "none">
    - Priority: <priority, or "Low">
    - Estimate: <estimate, or "none">
    - State: <state, or "To Do">

    **Description**

    ```
    <full issue description markdown, exactly as it would be sent to Jira>
    ```

All other rules in this skill (title conventions, section structure, acceptance criteria style,
etc.) apply identically regardless of mode.

## MCP call flow (mcp mode)

For non-trivial issue creation, the skill composes several Atlassian MCP calls in order:

1. **Look up the cloudId** via `getAccessibleAtlassianResources`. Look up once per session and
   reuse. If the user has multiple Atlassian sites, ask which one to use.
2. **Resolve the space** via `getVisibleJiraProjects` using the `space` value from `.jira.yml` as
   a search string. Pass the resulting `projectKey` to later calls.
3. **Resolve the assignee's accountId** via `lookupJiraAccountId` using the email or display name
   from `.jira.yml`.
4. **Create the issue** via `createJiraIssue`:
   - `summary`: the title.
   - `issueTypeName`: always `Task` (see "Default Field Values" below).
   - `description`: sent as markdown with `contentFormat: "markdown"`. See "Description format" below.
   - `additional_fields`: set `priority` (by name), `assignee` (by `accountId`), and
     `timetracking.originalEstimate` (as a duration string).
5. **Transition to the desired state**, if the configured `state` is not `To Do`:
   - Call `getTransitionsForJiraIssue` (cache the result per space for the session - transition
     IDs are stable within a project).
   - Call `transitionJiraIssue` with the matching transition ID.
6. **Create issue links**, if the user explicitly asked for blocking or related links - see
   "Blocking / linking" below.

## Description format

Pass descriptions as markdown (`contentFormat: "markdown"`). Jira renders `### Header`, `---`,
`- ` bullets, and `- [ ]` / `- [x]` checkbox lines acceptably - checkboxes appear as bullet-style
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

## Default Field Values

When creating issues unless the user specifies otherwise and no `.jira.yml` config is present:
- **Assignee**: Anurag, resolved via `lookupJiraAccountId` using `anurag.devanapally@gmail.com`.
- **Issue type**: always `Task`. Even bug titles (starting with "Fix ") are filed as Tasks - the
  "Fix " prefix does the sorting in the UI; issue type stays constant.
- **Space**: do not set. Leave blank so the issue lands in triage.
- **Priority**: `Low`. Jira requires a priority value, so the default is `Low` rather than unset.
- **State**: `To Do` (Jira's default for new issues).

Do not set labels, components, or estimates unless the user explicitly provides them or they come
from `.jira.yml`.

## Blocking / linking

Only create issue links when the user explicitly requests them or references a dependency in the
conversation. Use `createIssueLink`:

- `Blocks`: `inwardIssue` is the blocker, `outwardIssue` is the blocked issue.
- `Relates`: either direction (symmetric).
- `Duplicate`: `inwardIssue` is the duplicate, `outwardIssue` is the original.

Call `getIssueLinkTypes` first if you're unsure which link types exist on the site.

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
