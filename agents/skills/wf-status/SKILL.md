---
name: wf-status
description: Report where every in-flight thread stands, joining each work item's Plane state to what its branch and pull request show. Use this skill whenever the user says "/wf-status", "where does everything stand", "what's in flight", "status of my branches", or any variation of wanting a cross-worktree view of work in progress. Do NOT trigger for the state of one specific work item, which is a Plane lookup rather than a sweep.
---

# Work Status

Join what git and `gh` know to what Plane holds, and say where they disagree.

## Output

This skill's whole purpose is its report, so the report is not silent. Everything else is: announce no step, restate no command.

A disagreement is the point of running this. Never fold one into a summary line - each gets its own line naming what Plane says and what the branch or pull request shows.

## Step 0: Resolve context

```bash
wf-status --porcelain <repo paths, or nothing for the current repo>
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
```

The first call takes whatever repo paths the user named, substituted literally - or none for the current repo.

`wf-status` exits `0` when every repo path resolved. It exits `1` when at least one repo path was not a git work tree but at least one row still printed: use the rows you got, and report each named path from its stderr as unreadable, on its own line, the way this skill reports every other unobservable condition. It exits `2` on a usage error or when no repo path resolved at all - stop and print its stderr.

The resolver exits `2` on a usage error or a missing `yq`, `3` on a `.wf.yml` that is present but wrong - either way stop and print its stderr. A broken config is the user's to fix, and guessing the state names would compare rows against names nobody configured.

Each porcelain row is seven tab-separated fields: `repo`, `worktree`, `branch`, `identifier`, `dirty`, `pr_state`, `pr_url`. `identifier` is `-` when the branch carries none. `pr_state` is one of `none`, `draft`, `ready`, `merged`, `closed`; `pr_url` is `-` when there is no PR. `dirty` is a file count, `prunable`, or `-` when it could not be observed.

## Step 1: Resolve each work item

For every row whose `identifier` is not `-`, call `workitem` with `action: "retrieve_by_identifier"`. Save the current state UUID and the project id.

- **A 404 or any not-found error** is not an error here - it is one of the disagreements this skill reports. Mark the row `identifier-not-found` and move on; do not reach for a near miss.
- **Found** - call `state` with `action: "list"` for that project id, and resolve the saved state UUID to its name and its `group`. Cache the state list per project - several rows usually share one.

A row whose `identifier` is `-` needs no lookup and carries no disagreement of its own.

Plane being unreachable for any reason other than the not-found case above does not fail the run. Keep and report every comparison already resolved for a row reached before the failure; only the rows not yet reached lose their Plane half - report their git and `gh` half alone and say Plane could not be reached for the rest. Same property as everywhere else in this step: one failure costs its own detail and never another row's.

## Step 2: Check each row against the correspondence

`agents/skills/wf-conventions/CONFIG.md` holds "## The state correspondence" - the table naming which state goes with which condition. Read it there rather than restating it here: `/wf-ship` writes states by deciding which row holds, and this skill reads the same rows, so a copy here would be a second place for the two to drift.

Skip a row whose identifier is `-` or came back `identifier-not-found` from Step 1 - the second is already its own disagreement, and neither has a work item to compare against.

**Check the guard first**, for every row that has one - the same guard `/wf-shape` and `/wf-ship` check before writing. If the work item's current state belongs to a state in that project's list whose `group` is `completed` or `cancelled`, this row's only check is the one condition that has no `states.*` key:

- **The branch has not merged** - `pr_state` is anything but `merged`. A closed pull request counts as not-merged here, the same as `draft`, `ready`, or `none`: closing a pull request without merging it is exactly what an abandoned change looks like.

Flag the row when that holds - Plane says the item is closed out, the branch says otherwise - and move to the next row. Do not also run the correspondence-row check below for a guarded row; the guard is why this condition has no key of its own.

**Check `pr_state` for `merged` next, before the correspondence rows.** All three correspondence rows describe work still in flight; a branch that has merged has already left that space, and `/wf-wrap` - not this skill - owns moving the work item the rest of the way, so until it runs the item's Plane state is expected to still sit wherever `/wf-ship` last left it. Flag nothing for this row and move to the next one. Do not fall through to the diff below for a merged branch. Neither merge strategy gives an honest answer: a squash merge never makes the branch tip an ancestor of `origin/<default>`, so `origin/<default>...HEAD` still lists every file the branch ever touched and resolves to the code-touching row, while a merge commit makes the diff empty and resolves to the docs-only row. Both are the wrong row for work that has already landed. Step 3 still prints `pr_state=merged` on the row, so a merged-but-not-yet-wrapped item stays visible; only the correspondence comparison is skipped.

**Only when neither the guard nor the merged check above fired**, resolve which correspondence row the evidence points to, in the same order `/wf-ship` resolves it - the pull request checked first, so the later stage wins on the case where more than one row holds at once:

1. **`pr_state` is `ready`** - the pull request's row is the one that holds. A `draft`, `closed`, or `none` pull request is not "open and not a draft," so none of those satisfy this row; fall through to the diff below and let the tree decide instead.
2. **Otherwise, diff the worktree against its repo's default branch.** The porcelain row does not carry that name, so resolve it per repo, once, and reuse it across that repo's rows. Verify the ref you are about to diff against, not a same-named local branch that may not track it - a repo can have a local `main` with no `origin/main`, or the reverse:

   ```bash
   git -C <repo> rev-parse --verify --quiet origin/main >/dev/null && echo main \
     || { git -C <repo> rev-parse --verify --quiet origin/master >/dev/null && echo master; }
   ```

   Empty means neither `origin/main` nor `origin/master` exists: this repo's rows cannot resolve this check. Report the condition as unobservable for those rows rather than letting git's error escape - it costs only this one check's detail, never the row's identifier, PR state, or the guard above.

   A `prunable` worktree (its directory is gone) cannot be diffed either; treat it the same way - unobservable, not an error.

   Otherwise: `git -C <worktree> diff --name-only origin/<default>...HEAD`.

   - Touches only `docs/` - the docs-only row is the one that holds.
   - Touches anything outside `docs/` - the other row is the one that holds.

Compare the work item's current state name (Step 1) against the name Step 0's resolver gave for the row that holds, matched by exact string. **Only compare against a name that actually appears in that project's state list** (also from Step 1) - a project that has not adopted these states has none of them among its state names, and comparing against a name Plane has never heard of would flag every row in it. When none of the three configured names appear in a project's list, skip the check for that project's rows and say so once, the same way `/wf-shape` and `/wf-ship` skip the write when no state matches.

Flag the row when the names differ.

## Step 3: Report

One line per worktree: identifier, repo, branch, Plane's state name, pull request state, and the `dirty` field whenever it is not `0`.

Then the disagreements, each on its own line, naming both sides - what Plane holds and what was observed. An identifier that resolved to nothing names the identifier and the branch it came from, not a Plane state. No disagreements: say so in one line.
