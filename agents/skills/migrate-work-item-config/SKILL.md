---
name: migrate-work-item-config
description: >
  Convert a repo's legacy work item config - .plane.yml, .linear.yml, or .jira.yml - into the
  current .workitems.<tracker>.yml shape. Use this skill when a repo still carries one of those
  filenames, when file-work-item or refine-work-item reports finding one, or when the user says
  "migrate the plane config", "rename .plane.yml", "convert this repo's tracker config", or asks
  why a work item skill can't find its settings in a repo that clearly has some.
---

# Migrate Work Item Config

Work item config used to live in `.plane.yml`, and before that in `.linear.yml` or `.jira.yml`.
It now lives in `.workitems.<tracker>.yml`, because the filename is what tells a repo apart from
one on a different tracker.

**Nothing falls back to the old names.** A repo still carrying one is invisible to
`file-work-item` and `refine-work-item`, which will report it as having no config at all. That is
deliberate - a silent fallback is a migration that never finishes - and this skill is the thing
that finishes it.

This skill is temporary by design. See "Retiring this skill" at the bottom.

## Step 1: Find what the repo has

```bash
ls -1a <repo>/.plane.yml <repo>/.linear.yml <repo>/.jira.yml \
       <repo>/tmp/.plane.yml <repo>/tmp/.linear.yml <repo>/tmp/.jira.yml 2>/dev/null
ls -1a <repo>/.workitems.*.yml <repo>/tmp/.workitems.*.yml 2>/dev/null
```

Both locations matter: `tmp/` is where public repos keep this config, and a legacy file there is
exactly as invisible as one at the root.

Four cases:

- **Only legacy files** - the normal case. Migrate.
- **Only current files** - nothing to do. Say so and stop.
- **Both** - stop and show the user what each holds. A half-finished migration is the one state
  where guessing which file is authoritative can quietly discard settings.
- **Neither** - nothing to migrate. If the user wanted config, `file-work-item` creates it.

## Step 2: `.plane.yml` → `.workitems.plane.yml`

This is a pure rename. The key set did not change, so the contents carry over untouched.

```bash
git mv <repo>/.plane.yml <repo>/.workitems.plane.yml
```

Use `git mv` in a git repo so history follows the file. Use plain `mv` only outside one.

Then read the renamed file and fix two things if present:

- A comment referencing `plane-work-item-conventions`. That package is now
  `work-item-conventions`.
- A comment referencing `plane-create-work-item` or `plane-refine-work-item`. Those skills are now
  `file-work-item` and `refine-work-item`.

Do not add `default_tracker`. It only matters when a repo has more than one tracker config, and a
repo that just came off `.plane.yml` has exactly one.

## Step 3: `.linear.yml` or `.jira.yml` → `.workitems.plane.yml`

These predate Plane and hold a different key set, so this is a translation rather than a rename.
Read the old file, translate what it sets, and write a new `.workitems.plane.yml`.

**From `.linear.yml`:**

- `project` → `project`. Verify it matches a Plane project name or identifier; ask if uncertain.
- `state`: `Backlog`/`Todo` → a state in the project's `backlog` or `unstarted` group (commonly
  `Backlog` or `Todo`); `In Progress` → a `started` state; `Done`/`Canceled`/`Duplicate` → a
  `completed` or `cancelled` state. Confirm the real state name with `state` `list` before writing.
- `priority`: `1` → `urgent`, `2` → `high`, `3` → `medium`, `4` → `low`. Leave `0` unset so the
  default applies.
- `mode`, `assignee`: copy as-is. Verify the assignee matches a Plane workspace member.

**From `.jira.yml`:**

- `space` → `project`.
- `state`: `To Do` → an `unstarted` state, `In Progress` → a `started` state, `Done` → a
  `completed` state. Confirm with `state` `list`.
- `priority`: `Highest` → `urgent`, `High` → `high`, `Medium` → `medium`, `Low` and `Lowest` →
  `low`.
- `mode`, `assignee`: copy as-is. Verify the assignee matches a Plane workspace member.

A `.jira.yml` here is a *pre-Plane* artifact, not a Jira tracker config. If the user actually wants
this repo filing into Jira, that is `.workitems.jira.yml` and a different conversation - and
`references/jira.md` is still a skeleton, so say so.

### Removing the old file

Translating leaves the old file behind, and it has to go or the "both" case in Step 1 traps the
next run.

Print the exact removal command with an absolute path and ask the user to run it themselves.
Never delete it yourself, and never reach for `git rm` either - the deletion rules in `AGENTS.md`
apply here as everywhere else.

## Step 4: Confirm the repo resolves

The migration is done when the resolver agrees:

```bash
bash ~/.agents/skills/work-item-conventions/scripts/resolve-tracker.sh --repo-root <repo>
```

Exit `0` with `plane` on stdout means this repo is migrated. Anything else means it is not - read
the stderr line and fix what it names before calling it finished.

## Step 5: Report

One block, so a run through several repos reads as a list:

```text
Repo: ~/code/homelab
From: .plane.yml
To:   .workitems.plane.yml
Resolves: plane
Manual step: none
```

`Manual step:` names the removal the user still has to run, or `none`.

## Retiring this skill

This carries existing clones across a one-time rename. Retire it once every meaningful clone has
been through Step 4 and reports `Resolves:` - retiring earlier leaves a repo whose config silently
stops being read.

The legacy filename is handled in four places, and all four go at the same time:

- This skill directory. The README structure tree wildcards `agents/skills/*`, so nothing needs
  removing there.
- The paragraph in `wf-ship`'s Plane-link step saying a `.plane.yml` is deliberately not read.
- `plane_config_path`'s `basename` parameter and the `predates` skip reason in
  `bin/gh-set-default-settings`.
- The two `tests/gh-set-default-settings.bats` cases pinning that parameter and that message.
