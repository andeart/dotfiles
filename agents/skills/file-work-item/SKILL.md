---
name: file-work-item
description: >
  File a new work item in whatever tracker a repo uses - Plane, GitHub, Jira, or GitLab - written
  to Anurag's conventions. Use this skill whenever the user wants to create a work item that does
  not exist yet. Also trigger when the user says "make a work item", "make an issue", "create a
  ticket", "write a task", "log a bug", "file a bug", "report a problem", "open a GitHub issue",
  "file a Jira ticket", or describes a feature/bug/improvement they want tracked, even if they
  name no tracker. Do NOT trigger for improving, rewriting, or tidying a work item that already
  exists - that is refine-work-item.
---

# File Work Item

This skill files a new work item. It owns the flow and nothing else: the writing conventions live
in a shared file, and each tracker's mechanics live in a reference file beside it, so the same
request produces the same work item whichever tracker a repo happens to use.

Everything this skill reads is under `~/.agents/skills/work-item-conventions/`:

| File | What it holds |
| ---- | ------------- |
| `RESOLUTION.md` | How the tracker gets picked, and the resolver script's contract |
| `CONVENTIONS.md` | Title, description structure, acceptance criteria style, the estimate rule |
| `references/<tracker>.md` | Config keys, wire format, call flow, field defaults for one tracker |

## Step 1: Resolve the tracker

Do this first, before composing anything. What gets written depends on which tracker is answering,
and so does which config file is worth reading.

```bash
~/.agents/skills/work-item-conventions/scripts/resolve-tracker.sh \
  --repo-root <repo> [--tracker <name>]
```

Pass `--tracker` only when the user named one in the request - "open a GitHub issue", "file this in
Jira". Leave it off otherwise; a guess passed here silently outranks the repo's own config.

Handle the exit codes per `RESOLUTION.md`:

- `0` - stdout is the tracker. Carry on.
- `10` - stdout lists the candidates and stderr says why they couldn't be narrowed. Ask the user
  which to use, then offer to write `default_tracker` into the chosen tracker's config so the next
  generic request doesn't ask again. With no candidates at all, go to "No config at all" below.
- `2` - a usage error or an unknown tracker name. Stop and show it. An unknown name means the user
  asked for a tracker this repo has no mechanics for, which is a real answer, not a reason to fall
  back to detection.

## Step 2: Read the conventions and the one reference file

Read `CONVENTIONS.md`, then `references/<resolved>.md`.

**Only the resolved tracker's reference file.** The others describe trackers this run is not
filing into; loading them spends context on mechanics that cannot apply, and invites one tracker's
field names into another's call.

If the reference file says it is a skeleton, stop there and tell the user. Do not improvise the
mechanics from the other references.

## Step 3: Read the repo config

Read `.workitems.<tracker>.yml` - repo root first, then `tmp/`, root wins. The reference file's key
table says what the keys mean for this tracker.

Two rules hold on every tracker:

- **A key that is present applies without asking.** A key that is absent gets a question, unless
  the reference file's "Default field values" gives a fallback. User-provided values always beat
  the config.
- **If `guidance` is set, read it before composing.** It carries project-wide context - compliance
  rules, how work is split - that shapes wording and constraints. It is background, never a field.

### No config at all

Offer to create `.workitems.<tracker>.yml` before proceeding, and ask before writing. Write it with
every key from the reference file's table commented out, so the shape is discoverable and the user
can uncomment what they need:

```yaml
# mode:
# project:
# assignee:
# labels:
#   - name:
#     info: ""
# guidance: |
#   Project-wide context that isn't tied to a single entity.
```

For list-valued and annotated keys, comment out a shaped example rather than a bare key name.

If the repo has a `.plane.yml`, a `.linear.yml`, or a `.jira.yml` - the pre-rename and pre-Plane
filenames - do not silently ignore it. Hand it to `migrate-work-item-config`, which converts those
into the current shape.

### Keys missing from an existing config

After reading one, offer to append any supported keys it lacks, in commented form. Ask before
modifying the file. This is a convenience, not a blocker: a missing key that has a default does not
stop the run.

## Step 4: Compose

Write the title and the three sections per `CONVENTIONS.md`, in that tracker's wire format per the
reference file. Derive the estimate with the Fibonacci-from-hours rule.

## Step 5: Preview and get confirmation

Show the chat preview described in `CONVENTIONS.md` - rendered markdown, never the wire format,
with the estimate and its reasoning alongside. Wait for explicit confirmation before writing
anything.

Surface any module, label, or milestone you inferred here too. Those are content-dependent
guesses rather than fixed defaults, and they never get applied silently.

Manual mode is the exception to the shape, not to the confirmation: it shows the fenced wire format
because the user is the one pasting it.

## Step 6: Write, then report

Follow the reference file's create flow, then print the fields block from `CONVENTIONS.md`'s
"Reporting after the write" and nothing else. Build it from what this run already holds. Do not
re-read the work item to render it.
