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

This skill covers the mechanics of creating a new Jira issue: `.jira.yml` discovery, MCP call flow,
default field values, mode (mcp/manual), and linking. Writing conventions (title, description
structure, acceptance criteria style) live in a shared file so they stay consistent with the
refine skill.

**Before composing the issue body, Read `~/.claude/skills/jira-issue-conventions/CONVENTIONS.md`
and follow its rules for title, description format, description structure, and acceptance
criteria style.**

> **Terminology note.** Atlassian renamed Jira "projects" to "spaces" in the Cloud UI during the
> late-2025 rollout, but the REST API and MCP tools still use "project" (e.g. `projectKey`,
> `getVisibleJiraProjects`). This skill uses "space" everywhere it's user-facing (in `.jira.yml`,
> manual-mode output, and conversation), and translates to `project`/`projectKey` only when calling
> the Atlassian MCP tools.

## Repo-level defaults (.jira.yml)

Before creating an issue, check for a `.jira.yml` file in the repo root, or at `tmp/.jira.yml`
if the repo root doesn't have one. This file defines default field values for issues created from
this repo. The `tmp/.jira.yml` location is for public repos where a root-level `.jira.yml` (or a
`.gitignore` entry for it) would look out of place - `tmp/` is conventionally gitignored for
scratch/local files, so the config stays out of the committed tree without calling attention to
itself. If both exist, the root-level `.jira.yml` wins.

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

All rules in `CONVENTIONS.md` (title, section structure, acceptance criteria style, etc.) apply
identically regardless of mode.

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
   - `description`: sent as markdown with `contentFormat: "markdown"`. See the "Description format" section in `CONVENTIONS.md` for markdown/ADF guidance.
   - `additional_fields`: set `priority` (by name), `assignee` (by `accountId`), and
     `timetracking.originalEstimate` (as a duration string).
5. **Transition to the desired state**, if the configured `state` is not `To Do`:
   - Call `getTransitionsForJiraIssue` (cache the result per space for the session - transition
     IDs are stable within a project).
   - Call `transitionJiraIssue` with the matching transition ID.
6. **Create issue links**, if the user explicitly asked for blocking or related links - see
   "Blocking / linking" below.

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
