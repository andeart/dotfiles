# Plane: refining

The refine-side half of `plane.md`, split out so a filing run never loads it. Read it alongside
`plane.md`, whose config keys, wire format, estimates, and report block both flows share.

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

The keys `refine-work-item` reads as writing context rather than as defaults are `guidance` and the
`info` annotations on `modules`, `labels`, and `estimate_points`.

