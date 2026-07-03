---
name: plane-refine-work-item
description: >
  Refine an existing Plane work item so it matches Anurag's writing conventions. Use this skill
  whenever the user wants to improve, clean up, polish, rewrite, reshape, or tidy a work item that
  already exists in Plane. Also trigger when the user says "refine this work item", "rewrite this
  in our style", "make this work item conform", "fix up DX-22", "clean up this Plane work item",
  or points at a Plane work item identifier or URL and asks to improve its wording or structure.
  Do NOT trigger for creating new work items (use plane-create-work-item). Use alongside the
  Plane MCP tools (`retrieve_work_item_by_identifier`, `update_work_item`).
---

# Plane Refine Work Item

This skill rewrites an existing Plane work item's title and description so they match Anurag's
house conventions. The writing rules themselves live in a shared file that this skill and
`plane-create-work-item` both Read, so refined work items come out indistinguishable from freshly
created ones.

**Before proposing any rewrite, Read
`~/.agents/skills/plane-work-item-conventions/CONVENTIONS.md` and follow its rules for title,
description format, description structure, acceptance criteria style, and the Estimate section
(needed for the estimate-backfill step below).**

## Scope

Refining only touches **title** and **description**. It does not change:

- Assignee, priority, state, project, labels, modules, cycles.
- An **existing** estimate. A value that's already set is left untouched, exactly like the other
  fields above.
- Work item links, comments, work logs, or activity history.

The one exception is a **missing** estimate: if the fetched work item has no estimate assigned,
offer to backfill one per the "Estimate backfill" step below. This never overwrites an estimate
that's already present.

`.plane.yml` defaults are a *creation* concept and must not override an existing work item's
fields. If the user explicitly asks to also adjust a field (e.g. "and bump priority to High"),
handle that as a separate `update_work_item` call after the content rewrite is confirmed.

### Reference context from `.plane.yml`

`.plane.yml` field *defaults* remain out of scope — refining never changes
assignee, priority, state, modules, or labels, and never overwrites an estimate
that's already set (the sole field exception is backfilling a *missing* estimate,
per the Scope section and step 5 below). But two kinds of `.plane.yml` content are
*reference material for writing*, not defaults, and refine should read them for
context:

- `guidance` — project-wide constraints and conventions that inform wording
  (e.g. "never put PHI in descriptions").
- the `info` annotations on `modules` / `labels` / `estimate_points` — project
  terminology and semantics that help write accurate Notes.

Read them before proposing a rewrite. They shape the prose only; refine still
edits just `name`, `description_html`, and `description_stripped`.

## MCP call flow

1. **Fetch the current work item** via `retrieve_work_item_by_identifier` using the project
   identifier and sequence number from the user-provided reference (e.g. `DX-22` →
   `project_identifier: "DX"`, `issue_identifier: 22`). Pass `expand: "assignees,labels,state"`
   so you can see surrounding context. The response includes `description_html` (the current
   HTML body) and `description_stripped`. Note whether the work item already has an
   `estimate_point` set - a null/absent value is the trigger for the estimate-backfill step (5).
   Also read `.plane.yml` (repo root, or `tmp/.plane.yml`) if present, and load
   any `guidance` and entity `info` as context per "Reference context from
   `.plane.yml`" above before diagnosing or rewriting.
2. **Diagnose violations.** Compare the existing title and description against
   `CONVENTIONS.md`. Typical issues to look for:
   - Title does not start with "Fix " for a bug, or uses title case instead of sentence case, or
     describes symptoms rather than the deliverable.
   - Impact section missing, or written as "This fixes..." / "This adds..." instead of an
     outcome-oriented "This will...".
   - Notes and AC content intermingled, or AC items phrased as imperatives ("Add X") rather than
     declarative present tense ("X is added").
   - Acceptance criteria rendered as plain `<ul>` bullets instead of a task list
     (`<ul data-type="taskList">` / `<li data-type="taskItem" data-checked="false">`).
   - Testing step absent or not positioned last.
   - Section headers at the wrong level (e.g. `<h1>` or `<h2>` instead of `<h3>`), or `<hr>`
     separators missing between sections.
3. **Propose the rewritten version to the user before writing.** Render the preview in the
   human-readable form described in `CONVENTIONS.md` ("Previewing to the user before sending") -
   proposed title on its own line, then `### Impact` / `### Notes` / `### Acceptance criteria`
   sections with markdown bullets and `- [ ]` task items. Do not paste the raw HTML into chat;
   the compact single-line HTML is the wire format, not the preview format. Wait for explicit
   confirmation. Refining is destructive to existing prose, so never edit silently. If the user
   wants tweaks, iterate in chat first.
4. **Apply the edit** via `update_work_item` with the work item's UUID (from the retrieve call's
   `id` field) and its `project_id`. Pass only `name`, `description_html`, and
   `description_stripped` unless the user requested other field changes (or an estimate is being
   backfilled per step 5).
5. **Backfill the estimate if it's missing.** Only when the fetched work item had no
   `estimate_point` (step 1): derive one using the Fibonacci-from-hours rule in `CONVENTIONS.md`'s
   "Estimate" section, based on the scope described in the (rewritten) work item. Include the
   proposed estimate in the chat preview alongside the title/description rewrite (e.g.
   `Estimate: 5 (≈4h)`) and get confirmation with the rest. Resolve the value to a UUID and handle
   a missing `estimate_points` map or an out-of-set value exactly as `CONVENTIONS.md` describes
   (offer to discover and fill the map; on a value absent from the set, re-discover from the live
   project, and if still absent, stop and alert the user rather than snapping). The estimate-point
   discovery procedure itself lives in the `plane-create-work-item` skill's "Estimate points"
   section. Send the resolved `estimate_point` on the same `update_work_item` call as the content
   edit (step 4), or as a follow-up call if the content edit was already applied. If the work item
   already had an estimate, skip this step entirely - never overwrite it.

## Already well-formed

If the existing work item already satisfies the conventions, say so and make no edits to the
title or description. Summarize why no rewrite is needed (e.g. "Impact, Notes, and AC are all in
the right shape; title is sentence case and starts with 'Fix '; nothing to change.") rather than
forcing a rewrite just because the skill was invoked.

Even when the prose needs no rewrite, still check for a missing estimate and offer the backfill
(step 5) if one is absent - that's a separate, non-destructive add, not a content edit.

## Manual mode

If the work item's repo has `.plane.yml` with `mode: manual`, or if the user asks for manual
output, do not call `update_work_item`. Instead, present the rewritten title and description in
the same markdown format described in the `plane-create-work-item` skill's "Manual mode output
format" section, so the user can paste the refined version into Plane themselves.
