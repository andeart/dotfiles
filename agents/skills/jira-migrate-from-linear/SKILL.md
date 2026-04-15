---
name: jira-migrate-from-linear
description: >
  Migrate Linear issues to Jira - copies issues from a Linear project into a Jira project, preserving
  titles, descriptions, priorities, statuses, and links. Use this skill whenever the user wants to move,
  migrate, copy, or sync issues from Linear to Jira, even if they say something casual like "move my
  Linear stuff to Jira" or "copy those tickets over to Jira". Also trigger when the user mentions
  migrating between project trackers and both Linear and Jira are involved.
---

# Migrate Linear Issues to Jira

Move issues from a Linear project into a Jira project. The user provides a source Linear project and a
target Jira project (they may call it a "space" or "board" - these all mean the Jira project key).

## Required inputs

| Input | How the user provides it | Example |
|-------|--------------------------|---------|
| Source | A Linear project name **or** specific issue IDs | "FOSS", "BYA-77 and BYA-171" |
| Target Jira project | By name or key | "FOSS", "my FOSS Space" |

If the target is missing or ambiguous, ask before proceeding. If the user provides specific issue IDs,
no source project is needed.

## Workflow

### 1. Fetch Linear issues

**By project (default):** Use `list_issues` with the project name. Set `limit` to 250 and
`includeArchived` to false so you get all active issues without pulling in archived ones.

**By issue IDs:** Skip `list_issues` and go straight to step 3 (`get_issue`) for each ID the user
provided. This is useful when migrating a handful of issues rather than an entire project.

### 2. Resolve the Jira project

Use `getAccessibleAtlassianResources` to get the cloud ID, then `getVisibleJiraProjects` with a search
string matching the target name. Confirm the project key with the user if the search returns multiple
matches.

### 3. Get full issue details

The list endpoint truncates descriptions. Use `get_issue` on each issue with `includeRelations: true`
to get the complete description, attachments, status, and blocking relationships. Fetch all issues in
parallel.

### 4. Create Jira issues

For each Linear issue, create a Jira Task via `createJiraIssue` with:

- **summary**: The Linear issue title, unchanged.
- **description**: Use ADF format (`contentFormat: "adf"`). Structure the content as:
  1. A backlink to the original Linear issue at the top, italicized.
  2. If the issue was "In Progress" in Linear or has attachments (GitHub PRs, issues, etc.), add a
     metadata block noting the status and linking to those resources.
  3. A horizontal rule, then the full original description.
- **priority**: Map Linear priorities to Jira priorities by name (Urgent, High, Medium, Low). If
  Linear priority is "None", omit it.
- **additional_fields**: Use this for setting priority.

Create all issues in parallel when possible.

#### Why ADF instead of markdown

Jira's markdown renderer does not support `- [ ]` / `- [x]` checkbox syntax. Checkboxes render as
literal `[x]` text instead of native interactive checkboxes. ADF's `taskList`/`taskItem` nodes produce
real Jira checkboxes, so always use ADF when the description contains checkbox lists.

#### Converting checkboxes to ADF

Linear descriptions use `- [ ]` and `- [x]` for acceptance criteria. Convert these to ADF `taskList`
nodes. Each checkbox becomes a `taskItem` with a `localId` (use any unique string) and a `state` of
`"TODO"` or `"DONE"`:

```json
{
  "type": "taskList",
  "attrs": { "localId": "checklist-1" },
  "content": [
    {
      "type": "taskItem",
      "attrs": { "localId": "item-1", "state": "TODO" },
      "content": [{ "type": "text", "text": "GH PR is resolved" }]
    },
    {
      "type": "taskItem",
      "attrs": { "localId": "item-2", "state": "DONE" },
      "content": [{ "type": "text", "text": "File a GH issue." }]
    }
  ]
}
```

For the rest of the description (paragraphs, headings, horizontal rules, bullet lists, links, emphasis),
use the standard ADF node types (`paragraph`, `heading`, `rule`, `bulletList`, `listItem`,
`inlineCard`, `text` with marks, etc.).

### 5. Transition statuses

Jira issues are created in "To Do" by default. After creation, transition any issue whose Linear status
maps to a different Jira state. Use `getTransitionsForJiraIssue` to discover the available transition
IDs for the target project (they vary by project), then `transitionJiraIssue` to apply them.

| Linear status | Jira transition target |
|---------------|------------------------|
| Backlog | To Do (no transition needed) |
| Todo | To Do (no transition needed) |
| In Progress | In Progress |
| Done | Done |
| Canceled | Done (closest match - note in report) |
| Duplicate | Done (closest match - note in report) |

Only look up transitions once per project (the IDs are the same for all issues in the same project),
then apply them to each issue that needs it.

### 6. Create blocking relationships

If any Linear issues have `blockedBy` or `blocks` relations to other issues that are also part of this
migration, recreate those as Jira issue links after all issues have been created (you need the Jira keys
to exist first).

Use `createIssueLink` with type `"Blocks"`. The directionality is:
- `inwardIssue` = the blocker (the issue that blocks)
- `outwardIssue` = the blocked issue (the one waiting)

So if Linear says "BYA-10 is blocked by BYA-5", and those mapped to FOSS-3 and FOSS-1 respectively,
the link would be `inwardIssue: "FOSS-1"`, `outwardIssue: "FOSS-3"`, `type: "Blocks"`.

Skip relations where one side points to an issue outside the migration set (it won't have a Jira key).
Note any skipped relations in the report.

### 7. Report results

Show a summary table with columns: Linear ID, Jira key (linked), title, priority, and status.
If any blocking relationships were created or skipped, list those too.

## Priority mapping

| Linear | Jira |
|--------|------|
| Urgent | Highest |
| High | High |
| Medium | Medium |
| Low | Low |
| None | (omit) |

## Edge cases

- If the Linear project has no issues, say so and stop.
- If the Jira project doesn't exist, tell the user rather than trying to create one.
- If an individual issue fails to create, report the error and continue with the rest.
