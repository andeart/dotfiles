---
name: plane-create-work-item
description: >
  Conventions and formatting rules for writing Plane work items for Anurag.
  Use this skill whenever creating, editing, or reviewing Plane work items. Also trigger when the
  user asks to "make a work item", "make an issue", "create a ticket", "write a task", "log a bug",
  "file a bug", "report a problem", or describes a feature/bug/improvement they want tracked in
  Plane, even if they don't mention Plane by name. This skill covers work item structure, section
  ordering, sentence style, and acceptance criteria patterns. Use it alongside the Plane MCP tools
  (`create_work_item`, `list_work_items`, `list_states`, `get_workspace_members`, etc.).
---

# Plane Create Work Item

This skill covers the mechanics of creating a new Plane work item: `.plane.yml` discovery, MCP call
flow, default field values, mode (mcp/manual), and linking. Writing conventions (title, description
structure, acceptance criteria style) live in a shared file so they stay consistent with the
refine skill.

**Before composing the work item body, Read
`~/.agents/skills/plane-work-item-conventions/CONVENTIONS.md` and follow its rules for title,
description format, description structure, and acceptance criteria style.**

**If `.plane.yml` sets `guidance`, read it first as project-wide background — it
shapes wording and constraints (e.g. compliance rules) but is never itself a field.**

> **Terminology note.** Plane calls a tracked unit a **work item** (not "issue" or "ticket").
> The Plane MCP tools and this skill use that name everywhere. The user may say "issue" or
> "ticket" colloquially; treat those as synonyms for work item.

## Repo-level defaults (.plane.yml)

Before creating a work item, check for a `.plane.yml` file in the repo root, or at
`tmp/.plane.yml` if the repo root doesn't have one. This file defines default field values for
work items created from this repo. The `tmp/.plane.yml` location is for public repos where a
root-level `.plane.yml` (or a `.gitignore` entry for it) would look out of place - `tmp/` is
conventionally gitignored for scratch/local files, so the config stays out of the committed tree
without calling attention to itself. If both exist, the root-level `.plane.yml` wins.

Supported keys:

| Key | Description | Example |
| --- | ----------- | ------- |
| `mode` | `mcp` (default) or `manual` | `manual` |
| `workspace` | Plane workspace slug (the part after `app.plane.so/` in URLs). Required for any REST API fallbacks (e.g. `estimate_points` discovery); the MCP tools infer the workspace from the API token. | `byanu` |
| `project` | Plane project name or identifier (the prefix shown in work-item IDs, e.g. `DX` for `DX-22`). Resolved via `list_projects` to a project UUID. | `DX` |
| `assignee` | Plane display name or email (resolved via `get_workspace_members` to a user UUID) | `anurag` |
| `state` | Initial state name from the project's configured states | `Todo` |
| `estimate` | Story-point label from the project's configured estimate set (numeric labels are common). Must have a matching entry in `estimate_points` to be sent to Plane. | `2` |
| `estimate_points` | Map of estimate label → its estimate point. Each value is either a bare `estimate_point` UUID (legacy) or a `{ id, info }` map where `id` is the UUID and `info` documents what the point means. Required to send any estimate, since Plane's MCP API expects the UUID, not the integer label. See "Estimate points" and "Annotated entities" below. | `{1: {id: <uuid>, info: "Trivial"}}` |
| `modules` | List of the project's Plane modules, each `{ name, id?, info? }`. `info` describes what belongs in the module so the skill can pick the best fit. See "Annotated entities". | see below |
| `labels` | List of the project's labels, each `{ name, id?, info? }`. `info` describes when the label applies. See "Annotated entities". | see below |
| `states` | List of the project's states, each `{ name, info? }`, annotating what each state means. Informational only — the `state` key above still sets the default. | see below |
| `guidance` | Free-form prose (block scalar) with project-wide context not tied to a single entity (compliance rules, how work is split, etc.). Read as background before composing. | see below |
| `priority` | `urgent`, `high`, `medium`, `low`, `none` | `low` |

State and priority values are accepted case-insensitively but normalized before being sent to the
API (priority is lowercase; state is matched against the project's configured state names as-is).

When a key is present in `.plane.yml`, apply it automatically without asking. When a key is
absent, ask the user to choose a value before creating the work item (unless the "Default Field
Values" section below specifies a different fallback). User-provided values always override
`.plane.yml` defaults.

### Annotated entities

`modules`, `labels`, and `states` share one shape: a list of maps, each with a
required `name` and optional `id` (the Plane UUID, needed for MCP assignment) and
`info` (a semantic hint the skill reasons over when deciding whether the entry
applies). The uniform shape lets new entity kinds be added later without inventing
a new convention.

```yaml
modules:
  - name: Billing
    id: <uuid>
    info: "Subscriptions, invoices, Stripe webhooks, dunning. Anything money-in."
  - name: Onboarding
    info: "New-user signup and first-run experience."

labels:
  - name: tech-debt
    info: "Use when the item's primary value is reducing future friction, not user-facing."

states:
  - name: Blocked
    info: "Waiting on an external dependency; note the blocker in the description."
```

An entry with no `id` is guidance-only: the skill can reason about it but must
resolve or ask for the UUID before assigning it via MCP.

**Estimate semantics.** `estimate_points` accepts two value forms. The legacy bare
UUID still works; the annotated form adds an `info` string:

```yaml
estimate_points:
  1: { id: <uuid>, info: "Trivial. Under an hour." }
  2: { id: <uuid>, info: "Half a day. Single well-understood change." }
  5: <uuid>          # legacy bare-UUID form, still valid
```

When resolving an estimate: if the value is a map, use its `id`; if it's a bare
string, the value *is* the UUID.

**`guidance`** is a free-form block scalar for project-wide context that doesn't
attach to any single entity (compliance rules, how work is split into items, etc.).
Read it as background before composing the body; it shapes wording and constraints
but is never itself a field.

### Migrating from an existing .linear.yml or .jira.yml

If a `.linear.yml` or `.jira.yml` exists in the repo root (from the pre-Plane era), do not
silently ignore it. Offer to migrate its values into a new `.plane.yml` first.

**From `.linear.yml`:**

1. Read the values (if any are set).
2. Translate them:
   - `project` → `project` (verify it matches a Plane project name or identifier; ask if uncertain).
   - `state`: map `Backlog`/`Todo` → a state in the project's `backlog` or `unstarted` group
     (commonly `Backlog` or `Todo`); `In Progress` → a `started` state (commonly `In Progress`);
     `Done`/`Canceled`/`Duplicate` → a `completed` or `cancelled` state. Confirm the actual state
     name with `list_states` before writing.
   - `priority`: map `1` (Urgent) → `urgent`, `2` (High) → `high`, `3` (Medium) → `medium`,
     `4` (Low) → `low`. Leave `0` (None) unset so the default (`low`) kicks in.
   - `mode`, `assignee`: copy as-is. Verify the assignee matches a Plane workspace member.
   - `estimate`: leave unset. Linear story points and Plane estimates often use different scales.

**From `.jira.yml`:**

1. Read the values (if any are set).
2. Translate them:
   - `space` → `project`.
   - `state`: map `To Do` → an `unstarted` state, `In Progress` → a `started` state,
     `Done` → a `completed` state. Confirm with `list_states`.
   - `priority`: map `Highest` → `urgent`, `High` → `high`, `Medium` → `medium`, `Low` → `low`,
     `Lowest` → `low`.
   - `mode`, `assignee`: copy as-is. Verify the assignee matches a Plane workspace member.
   - `estimate`: leave unset. Jira's time-tracking durations (`3h`, `1d 4h`) don't translate to
     Plane's story-point estimates.

After writing `.plane.yml`, offer to delete the old `.linear.yml` / `.jira.yml`. Ask for
confirmation explicitly; never delete without it.

### Missing .plane.yml

If no `.plane.yml` (and no `.linear.yml` / `.jira.yml`) exists in the repo root, offer to create
`.plane.yml` before proceeding. Ask the user for confirmation first. If they accept, create the
file with all supported keys commented out so they can uncomment and set values as needed:

```yaml
# mode: mcp
# workspace:
# project:
# assignee:
# state:
# estimate:
# priority:
# estimate_points:
#   1: { id: <uuid>, info: "" }
#   2: { id: <uuid>, info: "" }
#   5: { id: <uuid>, info: "" }
# modules:
#   - name:
#     id: <uuid>
#     info: ""
# labels:
#   - name:
#     info: ""
# states:
#   - name:
#     info: ""
# guidance: |
#   Project-wide context that isn't tied to a single module/label/estimate.
```

### Missing keys in existing .plane.yml

After reading an existing `.plane.yml`, if any supported keys are absent, offer to append them in
commented form. This makes it easy for the user to uncomment and set values later rather than
looking up property names. For the list-valued keys (`modules`, `labels`, `states`) and the
annotated `estimate_points` form, append a shaped commented example (a `- name:` / `id:` / `info:`
entry, or a `{ id, info }` value) rather than a bare key, so the structure is discoverable. Ask for
confirmation before modifying the file.

## Mode

The `mode` key in `.plane.yml` (or a user-provided override) controls how the work item is
delivered. If no mode is configured, default to `mcp`.

- **`mcp`** - Create the work item directly via Plane MCP tools (`create_work_item`, etc.). This
  is the default.
- **`manual`** - Do not call Plane MCP tools. Instead, output the fully composed work item (title,
  description, and field values) as Markdown in the response so the user can copy-paste it into
  Plane.

### Manual mode output format

When `mode` is `manual`, present the title and fields as rendered markdown, then wrap the entire
description in a fenced code block so the user can copy-paste it into Plane's editor. Plane's
editor will accept HTML on paste. This mode is the safety valve for cases where direct MCP
access isn't available (e.g. expired token).

Example structure:

````markdown
**Title:** <work item title>

**Fields**
- Assignee: <assignee>
- Project: <project, or "none">
- Priority: <priority, or "low">
- Estimate: <estimate, or "none">
- State: <state, or "default">

**Description (HTML)**

```html
<full work item description HTML, exactly as it would be sent to Plane>
```
````

All rules in `CONVENTIONS.md` (title, section structure, acceptance criteria style, etc.) apply
identically regardless of mode.

## MCP call flow (mcp mode)

For non-trivial work item creation, the skill composes several Plane MCP calls in order:

1. **Resolve the project.** Call `list_projects` and match the `project` value from `.plane.yml`
   against the project's `identifier` (e.g. `DX`) or `name`. Cache the resolved `project_id`
   (UUID) per session - it's stable.
2. **Resolve the assignee's user UUID** via `get_workspace_members`. Match on `display_name` or
   `email`. Cache the result per session.
3. **Resolve the state UUID**, if a non-default `state` is configured. Call `list_states` for the
   project (cache the result per project per session - state IDs are stable within a project) and
   match by name (case-insensitive).
4. **Resolve the estimate point UUID**, if `estimate` is configured. Look up the integer label in
   the `estimate_points` map from `.plane.yml` and use the matching UUID. Do **not** rely on the
   `point` integer field on `create_work_item` / `update_work_item` - Plane's web UI reads the
   estimate from `estimate_point` (UUID) only, and the integer `point` field is silently ignored
   for display. There is no MCP tool that lists estimate points, so the map in `.plane.yml` is the
   only reliable source. If `estimate` is set but no matching entry exists in `estimate_points`,
   ask the user for the UUID rather than guessing or sending the integer.
5. **Create the work item** via `create_work_item`:
   - `project_id`: the project UUID.
   - `name`: the title.
   - `description_html`: the HTML body per `CONVENTIONS.md`.
   - `description_stripped`: the plain-text twin of the HTML body.
   - `priority`: the lowercase priority string (`urgent`, `high`, `medium`, `low`, `none`).
   - `assignees`: a list containing the assignee's user UUID.
   - `state`: the resolved state UUID, if specified.
   - `estimate_point`: the resolved estimate-point UUID, if specified.
6. **Add external links and relations**, if the user explicitly asked for them - see
   "Linking and relations" below.

### Applying modules and labels

Unlike `priority` or `assignee`, a module or label is not a fixed default — the
right one depends on what the work item is about. When `.plane.yml` defines
`modules` or `labels`:

1. Infer the best-fit entry by matching the work item's content against each
   entry's `info`. If nothing clearly fits, pick none rather than forcing one.
2. Surface the choice in what you propose to the user — never assign a module or
   label silently. In `manual` mode it appears in the fields block; in `mcp` mode
   state it before applying.
3. In `mcp` mode, assign the module after the work item is created, via
   `manage_module_work_items` using the module's `id`. If the chosen module has no
   `id` in `.plane.yml`, resolve it via `list_modules` (or ask) before assigning.
   Set labels via the `create_work_item` `labels` argument or `manage_work_item_label`
   using the resolved label id.

This does not loosen the guardrail in "Default Field Values": modules and labels
are still set only when they come from `.plane.yml` or the user, never invented.

### Estimate points

Plane stores each estimate as a UUID-keyed entry in a project-level "estimate set". The MCP API
exposes only the UUID (`estimate_point`) - there is no tool to list the set, and the integer
`point` field on work items is not what the UI displays. To set estimates reliably, record a
label-to-UUID map in `.plane.yml` under `estimate_points`.

**How to discover the UUIDs for a new project:**

Plane's MCP tools don't expose the estimate set, but the REST API does. If `PLANE_API_TOKEN` is
set in env and `workspace:` is set in `.plane.yml`, fetch the points directly:

```bash
# Resolve these three values first - they are NOT env vars; you must populate them yourself:
#   WORKSPACE   - the `workspace:` value from .plane.yml
#   PROJECT_ID  - the project's UUID from list_projects (`id` field)
#   ESTIMATE_ID - the project's `estimate` field from list_projects (the estimate set UUID)
# Only $PLANE_API_TOKEN is read from the environment.
WORKSPACE=...; PROJECT_ID=...; ESTIMATE_ID=...

# Endpoint verified against https://developers.plane.so/api-reference/estimate/list-estimate-points
curl -sS -H "X-API-Key: $PLANE_API_TOKEN" \
  "https://api.plane.so/api/v1/workspaces/$WORKSPACE/projects/$PROJECT_ID/estimates/$ESTIMATE_ID/estimate-points/" \
  | jq 'map({value, id})'
```

Each returned point has `value` (string label like `"2"`) and `id` (UUID). Translate the result
into the YAML `estimate_points:` map (YAML keys can be unquoted integers; the values are quoted
or unquoted UUID strings).

If `PLANE_API_TOKEN` is not set, fall back to the manual approach:

1. List existing work items (`list_work_items` with `fields=id,sequence_id,estimate_point`) and
   note the distinct `estimate_point` UUIDs in use.
2. For each unknown UUID, ask the user to read the rendered estimate value off any work item that
   uses it in the web UI.
3. Write the resulting label → UUID pairs into `.plane.yml` under `estimate_points`.

If the project has multiple historical estimate sets, you may see UUIDs that render the same label
(e.g. two different UUIDs both showing "2"). Keep only the canonical (current) one in the map and
note the orphan in a comment so future readers know not to use it.

## Default Field Values

When creating work items unless the user specifies otherwise and no `.plane.yml` config is
present:

- **Assignee**: Anurag, resolved via `get_workspace_members` matching `display_name: anurag` or
  `email: anurag.devanapally@gmail.com`.
- **Project**: Plane requires a `project_id` to create a work item. If neither `.plane.yml` nor
  the user supplied a project, ask which project to use before calling `create_work_item`.
- **Priority**: `low`. Plane accepts `none`, but `low` keeps the work item visible in
  priority-sorted views.
- **State**: do not pass `state`. Plane will use the project's default first state (typically
  something in the `backlog` or `unstarted` group).

Do not set labels, modules, cycles, or estimates unless the user explicitly provides them or they
come from `.plane.yml`. When `.plane.yml` lists `modules` or `labels`, select and apply them per
"Applying modules and labels" above (infer the best fit, surface it, never assign silently).

## Linking and relations

Only create links or relations when the user explicitly requests them or references a dependency
in the conversation.

**External URL links** (GitHub PRs, docs, dashboards, etc.): use `create_work_item_link` with the
work item UUID and the URL. Plane shows these in the work item's "Links" sidebar.

**Relations to other work items**: use `create_work_item_relation` with `relation_type` set to
one of:

- `blocking` - this work item blocks the listed ones.
- `blocked_by` - this work item is blocked by the listed ones.
- `relates_to` - symmetric.
- `duplicate` - this work item is a duplicate of the listed ones.
- `start_before` / `start_after` / `finish_before` / `finish_after` - scheduling relations,
  rarely used.

The `issues` argument is a list of work item UUIDs (not identifiers like `DX-22`). Resolve
identifiers via `retrieve_work_item_by_identifier` first if needed.
