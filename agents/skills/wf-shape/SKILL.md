---
name: wf-shape
description: Take a work item from premise verification through workspace setup to a brainstormed spec. Use this skill whenever the user says "/wf-shape", "let's start on DX-12", "pick up this work item", "shape this ticket", or any variation of beginning work on a tracked item that already exists. Do NOT trigger for filing a new work item - that is file-work-item - or for reviewing a spec that already exists, which is wf-spec-review.
---

# Shape a Work Item

Verify the work item's premises still hold, settle the questions that raises, then set up the workspace and hand off to brainstorming.

## Output

Happy-path steps produce no progress output. The premise comment, the questions, and the final hand-off line are what the user sees.

Every stop condition and every skipped step reports in full.

## Step 0: Resolve the identifier

The skill's argument when given. Otherwise the branch name's leading identifier (`dx-57-wf-config-foundation` -> `DX-57`).

If neither yields one, ask. Never guess and never scan the conversation for identifier-shaped strings: this skill posts a public comment on whatever it resolves, and a wrong identifier writes onto someone else's work.

## Step 1: Read the work item

Call the Plane MCP tool `workitem` with `action: "retrieve_by_identifier"`. Save `id`, `project`, and `state`.

On a not-found error, stop and say the identifier names nothing that exists. Do not reach for a near miss.

## Step 2: Verify the premises

Read every claim the work item makes - in its impact statement, its notes, and its acceptance criteria - and establish whether each still holds.

**Measure rather than reason.** A premise about the codebase is settled by reading the code or running the command, not by recalling what was true. A premise about another work item is settled by retrieving it. A premise you cannot measure is reported as unverified, not assumed.

Group findings as: what held, what needs correcting, and what you could not verify. State the date and what you measured against, so a later reader knows what the finding was true of.

**The findings live on the work item, not in the spec.** A measurement reaches the spec only where it changed a direction the work item had prescribed - there it belongs in the decision it justifies, dated. Everything else stays in the comment: a spec is re-read when the design is questioned, and a premise check that no longer matches the system rots there while still reading as authoritative.

## Step 3: Post the comment

Call `workitem_comment` with `action: "create"` and a `comment_html` body whose first element is `<h3>Re-verifying the ticket's premises</h3>`.

The title is fixed. `/wf-status` and later readers look for it.

## Step 4: Stop and surface the questions

Print the questions the premise pass raised and **stop**. Do not create a workspace, do not write a state, do not start a spec.

This is a hard gate, not a courtesy. Everything downstream depends on the answers, and a premise pass that ends by immediately building has not been read by anyone.

If the pass raised no questions and every premise held, say so in one line and continue to Step 5.

## Step 5: Create the workspace

Resolve the config in one call:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
```

Read `workspace.impl`:

- **`base`** - cut a branch from the current default branch: `git checkout -b <id-lowercase>-<short-kebab-slug> origin/<default>`. The slug comes from the work item's title, under 50 characters.
- **`worktree`** - use the `EnterWorktree` tool. Do not hand-roll `git worktree add`; the tool tracks what it created, which is what lets `/wf-wrap` tear it down.

## Step 6: Write the Shaping state

Read `states.shaping` from the resolver output. Call `state` with `action: "list"` and this project's id, and match that name exactly.

- **A state matches** - call `workitem` with `action: "update"`, passing only `state`. Report that the item moved.
- **No state matches** - skip the write and say so in one line. A project that has not adopted the stage states keeps working; this is deliberate for the trial. DX-59 turns the skip into a loud failure once the states exist everywhere.
- **The item already sits in a `completed` or `cancelled` state** - leave it alone and say so. Shaping work that is already closed is a signal to check the identifier, not to reopen it.

A Plane failure here never stops the run. The workspace exists and the spec is the point; report the failure and continue.

## Step 7: Hand off

Invoke `superpowers:brainstorming` for this work item. That skill owns the spec from here.

Report in one line: the identifier, the workspace created, and the state outcome.
