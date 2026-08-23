# Plane: creating

The create-side half of `plane.md`, split out so a refine run never loads it. Read it alongside
`plane.md`, whose config keys, wire format, and report block both flows share.

## Applying the config

When a key is present, apply it without asking. When one is absent, ask before writing, unless
"Default field values" below gives a fallback. User-provided values override the config.

## Creating

1. **Resolve the project.** `project` `list`, matching the config's `project` against each
   project's `identifier` (e.g. `DX`) or `name`. Cache the UUID per session - it's stable.
2. **Resolve the assignee.** `member` `list_workspace`, matching `display_name` or `email`. Cache
   per session.
3. **Resolve the state UUID**, if a non-default `state` is configured. `state` `list` for the
   project (cache per project per session - state IDs are stable within a project), matched by name
   case-insensitively.
4. **Resolve the estimate point.** Derive the value per `CONVENTIONS.md`, then map it through
   `estimate_points` - see `plane.md`'s "Estimates".
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
  custom definition rather than a `relation_type` value, and custom definitions are a paid feature.
  `AGENTS.md` records that `list_definitions` always answers HTTP 402 on this workspace's plan, so
  do not probe for one. Say the workspace can only express dependencies, and offer the closest
  `relation_type` instead.

## Default field values

When the user says nothing on the point and no config supplies one:

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
