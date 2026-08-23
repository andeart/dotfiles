---
name: refine-work-item
description: >
  Rewrite an existing work item - in Plane, GitHub, Jira, or GitLab - so it matches Anurag's
  writing conventions. Use this skill whenever the user wants to improve, clean up, polish,
  rewrite, reshape, or tidy a work item that already exists. Also trigger when the user says
  "refine this work item", "rewrite this in our style", "make this work item conform", "fix up
  DX-22", "clean up this issue", or points at a work item identifier or URL and asks to improve
  its wording or structure. Do NOT trigger for creating a work item that does not exist yet -
  that is file-work-item.
---

# Refine Work Item

This skill rewrites an existing work item's title and description so they match Anurag's house
conventions. It reads the same shared conventions `file-work-item` does, so a refined work item
comes out indistinguishable from a freshly filed one - on any tracker.

Everything this skill reads is under `~/.agents/skills/work-item-conventions/`:

| File | What it holds |
| ---- | ------------- |
| `RESOLUTION.md` | How the tracker gets picked, and the resolver script's contract |
| `CONVENTIONS.md` | Title, description structure, acceptance criteria style, the estimate rule |
| `references/<tracker>.md` | Fetch and update mechanics, wire format, diagnosis hints for one tracker |

## Scope

Refining touches **title** and **description**, and nothing else. It does not change assignee,
priority, state, project, labels, modules, milestones, or cycles. It does not touch links,
comments, work logs, or activity history.

It does not change an **existing** estimate either. A value already set is left alone, exactly like
the fields above.

The one exception is a **missing** estimate: when the fetched work item has none, offer to backfill
one. That is a non-destructive add, not a content edit, so it is offered even when the prose itself
needs no rewrite.

Repo config holds *creation* defaults, and those must not override an existing work item's fields.
If the user explicitly asks to adjust a field as well - "and bump priority to high" - handle it as a
separate update after the content rewrite is confirmed.

## Step 1: Resolve the tracker

A work item identifier is not a tracker. `DX-22` and `PROJ-123` are shaped alike, and `#41` says
nothing at all, so resolve before fetching rather than guessing from what the user typed.

```bash
~/.agents/skills/work-item-conventions/scripts/resolve-tracker.sh \
  --repo-root <repo> [--tracker <name>]
```

Pass `--tracker` only when the user named one. Handle exit codes per `RESOLUTION.md`: `0` carries
on, `10` asks the user which candidate to use, `2` stops.

A work item URL in the request is the exception worth noticing - the host names the tracker
outright, so pass it as `--tracker` rather than running detection against a repo the user may not
even be standing in.

## Step 2: Read the conventions and the one reference file

Read `CONVENTIONS.md`, then `references/<resolved>.md` and only that one. If the reference file
says it is a skeleton, stop and tell the user.

## Step 3: Fetch the work item

Follow the reference file's refine flow. Note whether an estimate is already set - its absence is
what enables step 6.

### Reference context from the repo config

Field *defaults* stay out of scope, per Scope above. But two kinds of config content are reference
material for *writing* rather than defaults, and refining should read them:

- `guidance` - project-wide constraints that inform wording (e.g. "never put PHI in
  descriptions").
- the `info` annotations on labels, modules, and estimate entries - project terminology and
  semantics that help write accurate Notes.

They shape the prose only. Refining still writes just the title and the description.

## Step 4: Diagnose

Compare the existing title and description against `CONVENTIONS.md`. Typical breakages, on any
tracker:

- Title doesn't start with "Fix " for a bug, or uses title case instead of sentence case, or
  describes symptoms rather than the deliverable.
- Impact missing, or written as "This fixes..." / "This adds..." instead of an outcome-oriented
  "This will...".
- Notes and acceptance criteria intermingled, or criteria phrased as imperatives ("Add X") rather
  than declarative present tense ("X is added").
- Acceptance criteria rendered as plain bullets instead of interactive checkboxes.
- Testing step absent, or not last.
- Section headers at the wrong level, or the rules between sections missing.

The reference file lists the breakages specific to its tracker's markup on top of these.

## Step 5: Propose, then apply

Show the rewrite in the chat preview form from `CONVENTIONS.md` - rendered markdown, never the wire
format. Wait for explicit confirmation.

**Refining destroys existing prose, so never edit silently.** If the user wants tweaks, iterate in
chat before writing anything.

Then apply via the reference file's update flow, sending only the title and description fields.

## Step 6: Backfill a missing estimate

Only when step 3 found none. Derive one with the Fibonacci-from-hours rule against the scope the
rewritten work item describes, and include it in the same preview so it gets confirmed alongside
the prose:

```text
Estimate: 5 (≈4h)
```

Send it on the same update call as the content edit where the tracker allows it, or as a follow-up
if the content edit already landed. The reference file says how that tracker records an estimate,
including the case where it has nowhere to put one.

If the work item already had an estimate, skip this entirely. Never overwrite one.

## Step 7: Report

Print the fields block from `CONVENTIONS.md`'s "Reporting after the write". Every field in it either
came back on the fetch or was set by this run, so nothing here needs a second read.

## Already well-formed

If the work item already satisfies the conventions, say so and change nothing. Summarize why no
rewrite is needed - "Impact, Notes, and AC are all in the right shape; title is sentence case and
starts with 'Fix'; nothing to change" - rather than forcing a rewrite just because the skill was
invoked.

Then still check for a missing estimate and offer the backfill.

## Manual mode

If the repo config sets `mode: manual`, or the user asks for manual output, write nothing. Present
the rewritten title and description in the manual-mode format the reference file describes, so the
user can paste it in themselves.
