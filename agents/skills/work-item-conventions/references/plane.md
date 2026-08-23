# Plane

Native noun: **work item**. Plane does not say "issue" or "ticket" anywhere in its UI or its MCP
tools, so neither should output for this tracker.

Identifiers look like `DX-22` - a project prefix, a hyphen, a number. Plane's editor turns a bare
identifier in a description into a mention chip, so reference other work items that way rather
than as links.

## Config: `.workitems.plane.yml`

| Key | Description | Example |
| --- | ----------- | ------- |
| `mode` | `mcp` (default) or `manual` | `manual` |
| `workspace` | Workspace slug (the part after `app.plane.so/` in URLs). Used to link the identifier in the report; without it the report prints a bare identifier. The MCP tools infer the workspace from the API token, so it isn't required to write. | `acme` |
| `project` | Project name or identifier (the prefix in work item IDs, e.g. `DX` for `DX-22`). Resolved via `project` `list` to a UUID. | `DX` |
| `assignee` | Display name or email, resolved via `member` `list_workspace` to a user UUID | `anurag` |
| `state` | Initial state name from the project's configured states | `Todo` |
| `priority` | `urgent`, `high`, `medium`, `low`, `none` | `low` |
| `estimate_points` | Map of Fibonacci label → estimate point. Each value is a bare `estimate_point` UUID (legacy) or a `{ id, info }` map. Required to send any estimate at all. | `{1: {id: <uuid>, info: "up to 1h"}}` |
| `modules` | The project's modules, each `{ name, id?, info? }` | see below |
| `labels` | The project's labels, each `{ name, id?, info? }` | see below |
| `guidance` | Free-form prose (block scalar) with project-wide context not tied to one entity | see below |

`default_tracker` is also accepted here; it belongs to resolution, not to Plane, and
`RESOLUTION.md` covers it.

State and priority are accepted case-insensitively but normalized before being sent: priority
lowercase, state matched against the project's configured state names as-is.

When a key is present, apply it without asking. When one is absent, ask before writing, unless
"Default field values" below gives a different fallback. User-provided values always override the
config.

**If `guidance` is set, read it first** as project-wide background. It shapes wording and
constraints (e.g. compliance rules) but is never itself a field.

### Annotated entities

`modules` and `labels` share one shape: a list of maps, each with a required `name` and optional
`id` (the UUID, needed for MCP assignment) and `info` (a semantic hint to reason over when
deciding whether the entry applies). The uniform shape lets new entity kinds be added later
without inventing a new convention.

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
```

An entry with no `id` is guidance-only: reason about it, but resolve or ask for the UUID before
assigning it.

`estimate_points` accepts the same two value forms:

```yaml
estimate_points:
  1: { id: <uuid>, info: "Trivial. Under an hour." }
  2: { id: <uuid>, info: "Half a day. Single well-understood change." }
  5: <uuid>          # legacy bare-UUID form, still valid
```

When resolving: if the value is a map, use its `id`; if it's a bare string, the value *is* the
UUID.

## Wire format

Plane stores descriptions as HTML in `description_html`. The `workitem` MCP tool's `create` and
`update` accept HTML directly, and Plane's Tiptap editor normalizes it on save: it adds its own
Tailwind classes (`editor-paragraph-block`, `list-disc pl-7 space-y-(--list-spacing-y) tight`) and
a fresh `data-id` to every block. Send the minimal markup below and let Plane normalize.

Verified by round-tripping through `workitem` `retrieve_by_identifier`:

- `<p>...</p>` for paragraphs.
- `<h1>` through `<h6>` for headings. Plane preserves the level and adds its own
  `class="editor-heading-block"` and `data-id`. `CONVENTIONS.md` puts the section headers at the
  third level, so use `<h3>`.
- `<ul><li>...</li></ul>` for bullet lists. Plane wraps the `<li>` text in its own `<p>` on save -
  don't do it yourself.
- Nested bullets: a `<ul>` directly inside an `<li>`.
- Acceptance criteria use Tiptap's task-list markup:

  ```html
  <ul data-type="taskList">
    <li data-type="taskItem" data-checked="false">A notification is sent when …</li>
    <li data-type="taskItem" data-checked="true">The behavior is tested with …</li>
  </ul>
  ```

  The `data-type` attributes are what Plane keys off to render real interactive checkboxes (with
  `<label><input type="checkbox">` markup). Without them, Plane treats the markup as a plain
  bullet list.
- Horizontal rules use Plane's nested-div markup:

  ```html
  <div data-type="horizontalRule"><div></div></div>
  ```

  The `data-type` is the signal; the inner empty `<div>` is required. Plane fills in its own
  Tailwind classes (`py-4 border-strong-1`) on save. A plain `<hr>` is untested - it may or may
  not normalize to this form, so prefer the verified markup.
- `<strong>`, `<u>`, `<em>` for bold, underline, italic. `<a href="…">…</a>` for external links.

Also pass `description_stripped` with the plain-text version (no tags, single newlines between
blocks). Plane uses it for search and previews.

### Whitespace between tags

Send `description_html` as one continuous string with **no whitespace between block-level tags**.
Tiptap turns inter-tag whitespace (newlines, indentation) into empty paragraph blocks on save,
which render as blank bullets and large vertical gaps. Specifically:

- No newlines between `</ul>` and the next `<h3>` or `<div data-type="horizontalRule">`.
- No newlines or indentation between `<ul>` and its first `<li>`, or between sibling `<li>`s.
- No newlines between sections of any kind.

This applies to both `create` and `update`. The example at the bottom is intentionally on a single
line - copy that shape, don't pretty-print.

## Report fields

After `Issue:` and `Assignee:`, in this order: `State`, `Priority`, `Estimate`, `Cycle`, `Module`,
`Labels`.

`Issue:` links as `[<ID>](https://app.plane.so/<workspace>/browse/<ID>/)` when `workspace` is set,
keeping the trailing slash, and prints the bare identifier when it isn't.

## Creating

1. **Resolve the project.** `project` `list`, matching the config's `project` against each
   project's `identifier` (e.g. `DX`) or `name`. Cache the UUID per session - it's stable.
2. **Resolve the assignee.** `member` `list_workspace`, matching `display_name` or `email`. Cache
   per session.
3. **Resolve the state UUID**, if a non-default `state` is configured. `state` `list` for the
   project (cache per project per session - state IDs are stable within a project), matched by name
   case-insensitively.
4. **Resolve the estimate point.** Derive the value per `CONVENTIONS.md`, then map it through
   `estimate_points` - see "Estimates" below.
5. **Create** via `workitem` `create`:
   - `project_id`: the project UUID.
   - `name`: the title.
   - `description_html`: the HTML body.
   - `description_stripped`: its plain-text twin.
   - `priority`: the lowercase priority string.
   - `assignees`: a list holding the assignee's user UUID.
   - `state`: the resolved state UUID, if specified.
   - `estimate_point`: the resolved estimate-point UUID, if specified.
6. **Add links and relations** only if the user asked - see "Links and relations".
7. **Report** from the values resolved above, not from a re-read.

## Refining

1. **Fetch** via `workitem` `retrieve_by_identifier`, passing the reference whole as
   `workitem_identifier` (e.g. `DX-22`) - the tool takes the full identifier, not the prefix and
   number separately. Pass `expand: "assignees,labels,state"` for surrounding context. The response
   carries `description_html` and `description_stripped`. Note whether `estimate_point` is set; a
   null or absent value is what triggers the backfill.
2. **Apply** via `workitem` `update`, with `workitem_id` set to the retrieve's `id` field and
   `project_id` to its `project`. The parameter is `workitem_id`, not `work_item_id`. Pass only
   `name`, `description_html`, and `description_stripped` unless the user asked for other field
   changes or an estimate is being backfilled.

Diagnose against `CONVENTIONS.md`, plus these Plane-specific breakages:

- Acceptance criteria as plain `<ul>` bullets instead of `<ul data-type="taskList">` /
  `<li data-type="taskItem" data-checked="false">`.
- Section headers at the wrong level (`<h1>` or `<h2>` instead of `<h3>`).
- `<hr>` separators missing between sections, or written as a plain `<hr>`.

### Reference context from the config

Field *defaults* stay out of scope when refining. But two kinds of config content are reference
material for writing rather than defaults, and refine should read them: `guidance`, and the `info`
annotations on `modules` / `labels` / `estimate_points`. They shape the prose only.

## Estimates

Plane stores each estimate as a UUID-keyed entry in a project-level estimate set, and `create` /
`update` take that UUID via `estimate_point`. **Do not rely on the integer `point` field** - the
web UI reads the estimate from `estimate_point` only, and `point` is silently ignored for display.
Never guess a UUID or send the bare integer.

Map the chosen Fibonacci value through `estimate_points` (if the entry is a `{ id, info }` map, use
its `id`; a bare string *is* the UUID). Then:

- **If `estimate_points` is missing or empty**, offer to discover the project's estimate set and
  write it into the config before assigning. Ask before modifying the file.
- **If the chosen value isn't in the set**, do not snap to a neighbouring point. Re-discover from
  the live project first - the map may be stale. If it's still absent, stop and alert the user: the
  convention is a Fibonacci scale, so a missing Fibonacci point almost always means the project's
  estimate set needs correcting, not that the estimate should be rounded to fit. Assign no estimate
  in that case.

Discover or refresh a project's set with two calls:

1. `project_estimate` `retrieve` with `project_id` - returns the active set; its `id` is the
   `estimate_id`.
2. `project_estimate` `list_points` with `project_id` and `estimate_id` - returns each point as an
   object with `value` (the display label, e.g. `"1"`, `"5"`) and `id` (the UUID to send).

Write the label → UUID pairs back under `estimate_points`, preferring the annotated form. YAML keys
may be unquoted integers. `retrieve` returns only the active set, so historical or orphaned points
rendering the same label never enter the map.

In manual mode there is no UUID to resolve; render the chosen number in the fields block.

## Modules and labels

Unlike priority or assignee, the right module or label depends on what the work item is about.
When the config defines them:

1. Infer the best fit by matching the work item's content against each entry's `info`. If nothing
   clearly fits, pick none rather than forcing one.
2. Surface the choice in what you propose - never assign silently. In `manual` mode it appears in
   the fields block; in `mcp` mode state it before applying.
3. Assign the module after creation, via `module` `manage_workitems` with the module's `id` as
   `module_id` and the work item UUID in `add_ids`. If the chosen module has no `id` in config,
   resolve it via `module` `list` or ask. Set labels via the `labels` argument on `create`, or
   afterwards via `workitem` `manage_label` with the label id in `add_label_id`.

This does not loosen "Default field values": modules and labels are still set only when they come
from config or the user, never invented.

## Links and relations

Only when the user explicitly asks, or references a dependency in the conversation.

**External URLs** (PRs, docs, dashboards): `workitem_link` `create` with `project_id`,
`workitem_id`, and `url`. Plane shows these in the Links sidebar.

**Relations to other work items**: `workitem_relation` `create` with `project_id`, `workitem_id`,
and `workitem_ids` - a list of UUIDs, not identifiers, so resolve identifiers via
`retrieve_by_identifier` first. Two kinds, taking different arguments:

- **Dependencies** go in `relation_type`: `blocking`, `blocked_by`, `start_before`, `start_after`,
  `finish_before`, `finish_after`. The scheduling four are rarely used.
- **Everything else** - symmetric "relates to", "duplicate", any workspace-defined relation - is a
  custom definition rather than a `relation_type` value. Call `list_definitions` first, match the
  user's wording to an entry, then pass its id as `relation_definition_id` and the matched `outward`
  or `inward` label as `relation_definition_label`; the label is what sets direction. Custom
  definitions are a paid feature, so `list_definitions` answering HTTP 402 means the workspace can
  only express dependencies.

## Default field values

When the user specifies otherwise and no config is present:

- **Assignee**: Anurag, via `member` `list_workspace` matching `display_name: anurag` or
  `email: anurag.devanapally@gmail.com`.
- **Project**: Plane requires `project_id` to create. If neither config nor the user supplied one,
  ask before calling `create`.
- **Priority**: `low`. Plane accepts `none`, but `low` keeps the work item visible in
  priority-sorted views.
- **State**: don't pass `state`. Plane uses the project's default first state.
- **Estimate**: always assign one. The only time none is set is when the resolution rules force a
  stop.

Do not set labels, modules, or cycles unless the user provides them or they come from config.

## Manual mode

When `mode` is `manual`, call no MCP tools. Present the title and fields as rendered markdown, then
the description fenced as HTML so it can be pasted into Plane's editor, which accepts HTML on
paste. This is the safety valve for when MCP access isn't available (e.g. an expired token).

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
<full description HTML, exactly as it would be sent>
```
````

Every rule in `CONVENTIONS.md` applies identically regardless of mode.

## Example

`CONVENTIONS.md`'s worked body as Plane wire format. It is a single line - wrapped here only by
page width. Send it with no newlines or indentation between tags:

```html
<h3>Impact</h3><ul><li>This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.</li></ul><div data-type="horizontalRule"><div></div></div><h3>Notes</h3><ul><li>Presence detection should use Wi-Fi presence as the primary method for the first version.</li><li>A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.</li><li>Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.</li></ul><div data-type="horizontalRule"><div></div></div><h3>Acceptance criteria</h3><ul data-type="taskList"><li data-type="taskItem" data-checked="false">Wi-Fi presence detection is set up for all tracked occupants.</li><li data-type="taskItem" data-checked="false">An automation triggers when all tracked occupants are detected as away.</li><li data-type="taskItem" data-checked="false">The automation locks all doors.</li><li data-type="taskItem" data-checked="false">An alert is sent if a door lock fails to lock.</li><li data-type="taskItem" data-checked="false">The behavior is tested with a simulated all-away state before relying on real presence detection.</li></ul>
```

The matching `description_stripped`. Section headers sit on their own line; horizontal rules are
dropped entirely, since Plane omits them from the stripped form:

```text
Impact
- This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.
Notes
- Presence detection should use Wi-Fi presence as the primary method for the first version.
- A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
- Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.
Acceptance criteria
- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
