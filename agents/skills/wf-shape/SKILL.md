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

The skill's argument when given. Otherwise the branch name's leading identifier, read the way `wf-wrap` reads it: strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)` and uppercase the prefix (`dx-57-wf-config-foundation` → `DX-57`; `worktree-dx-57-wf-config-foundation` → `DX-57`).

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

Once the user answers, resume at Step 5 with those answers folded into the premise findings.

If the pass raised no questions and every premise held, say so in one line and continue to Step 5.

## Step 5: Create the workspace

Resolve the config and the default branch in one call:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
echo "resolver_exit=$?"
[ -f "$(git rev-parse --show-toplevel)/.wf.yml" ] \
  && echo 'wfconfig_file=yes' || echo 'wfconfig_file=no'
origin=$(git remote get-url origin 2>/dev/null)
echo "origin=$origin"
[ -n "$origin" ] && git fetch --quiet origin
default=$(git rev-parse --verify --quiet main >/dev/null && echo main || { git rev-parse --verify --quiet master >/dev/null && echo master; })
echo "default=$default"
```

`resolver_exit=2` (a usage error or a missing `yq`) or `resolver_exit=3` (a `.wf.yml` that is present but wrong) - stop and print the resolver's stderr. A broken config is the user's to fix, and guessing a workspace mode would cut a branch where a worktree was asked for. Both print no dump at all, so there is nothing below to check.

The keys this skill reads:

- `workspace.impl` - whether this step cuts a branch or enters a worktree.
- `states.shaping` - the name Step 6 matches against the project's states.

Check every key in that list against the dump, with any trailing `.1`/`.2` dropped: a key is present when a line starts with `<key>=` or `<key>.`, and unset when that line is `<key>=<unset>`. On the happy path print nothing and continue.

**Any key unset** - stop, naming them all in one line:

> `workspace.impl` is unset in `.wf.yml`. Run `/wf-config` to set it, then retry.

**Every key in the list unset, and `wfconfig_file=no`** - collapse it instead:

> No `.wf.yml` in this repo. Run `/wf-config` to create one.

The probe is what earns the collapsed wording. An empty `.wf.yml`, a comments-only one and `review: {}` all resolve at exit 0 with every key `<unset>`, exactly as an absent file does, and the dump alone cannot tell them apart; `wfconfig_file=yes` names the keys instead.

`<none>` is never a halt - it is a list the file declared empty, deliberately.

The list is fixed rather than re-derived per run, so a guarded run that never reaches Step 6 can still halt on `states.shaping`. That is the cheaper of the two errors: a conditional list is a second thing to keep in step with the branch structure, and the cost of being wrong is a `/wf-config` run rather than a wrong write.

After running `/wf-config`, resume at this step rather than re-running the skill. Step 3's comment carries a fixed `<h3>` title that `/wf-status` and later readers match on, so a second run leaves two of them on the work item.

`origin=` empty - stop and tell the user no remote named `origin` is configured.

`default=` empty - neither `main` nor `master` exists; stop and say so.

Read `workspace.impl`:

- **`base`** - cut a branch from the current default branch: `git checkout -b <id-lowercase>-<short-kebab-slug> origin/<default>`. The slug comes from the work item's title, under 50 characters.
- **`worktree`** - use the `EnterWorktree` tool, passing `name` set to `<id-lowercase>-<short-kebab-slug>` - the same branch name the `base` path uses. Do not hand-roll `git worktree add`; the tool tracks what it created, which is what lets `/wf-wrap` tear it down.

## Step 6: Write the `states.shaping` state

1. Call `state` with `action: "list"` and `project_id` set to the project id Step 1 saved.
2. **Check the guard first.** If the state Step 1 saved belongs to a state in that list whose `group` is `completed` or `cancelled`, leave the item alone, report that, and stop here - do not read `states.shaping` at all. Compare against every state in those groups, not one named state: a project can close work items into more than one state.
3. Only past the guard, read `states.shaping` from Step 5's resolver output and match it by name, exactly, against the same list.
4. **No state matches** - skip the write and say so in one line. A project that has not adopted the stage states keeps working; this is deliberate for the trial. DX-59 turns the skip into a loud failure once the states exist everywhere.
5. **A state matches** - call `workitem` with `action: "update"`, passing only `state`. Report that the item moved.

A Plane failure here never stops the run. The workspace exists and the spec is the point; report the failure and continue.

## Step 7: Hand off

Invoke `superpowers:brainstorming` for this work item, telling it to lead the spec filename's `<topic>` with `<id-lowercase>` (`docs/superpowers/specs/YYYY-MM-DD-<id-lowercase>-<topic>-design.md`) - `/wf-spec-review` finds the spec by matching the identifier against the filename. That skill owns the spec from here.

Report in one line: the identifier, the workspace created, and the state outcome.
