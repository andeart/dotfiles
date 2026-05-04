---
name: wf-wrap
description: Wrap up work after a PR merges - switch back to the default branch, pull, delete the merged feature branch, and mark the corresponding Plane work item as Done. Use this skill whenever the user says "/wf-wrap", "wrap this up", "wrap up the merge", "post-merge cleanup", "switch back to main and clean up", or any variation of wanting to clean up after merging a PR. Do NOT trigger for shipping work for review (use /wf-ship) or for cleaning up older merged branches (use /wf-prune).
---

# Wrap Up After Merge

Run the post-merge cleanup sequence in one shot: switch back to the default branch, pull, mark the associated Plane work item as Done, then delete the just-merged feature branch. Strong precondition checks; no confirmations once they pass.

## Step 0: Detect context

Determine the default branch: check if `main` exists (`git rev-parse --verify main 2>/dev/null`), otherwise check `master`. Call this `<DEFAULT>`.

Run `git symbolic-ref --short HEAD` to get the current branch. Save it as `<FEATURE>`.

**If `<FEATURE>` IS `<DEFAULT>`**, stop immediately and tell the user:

> You're already on `<DEFAULT>` - nothing to wrap up. If you wanted to clean up older merged branches, use `/wf-prune`.

## Step 1: Safety checks

All of these must pass before any destructive action runs:

- Verify you're inside a git repo: `git rev-parse --is-inside-work-tree`.
- Verify `gh` is available on PATH.
- Verify the `origin` remote is configured: `git remote get-url origin`.
- Verify the working tree is clean: `git status --porcelain`. If it returns any output, stop with:

  > Uncommitted changes on `<FEATURE>` - handle them before wrapping.

Any failure stops the skill immediately with a message naming the specific failure. Do not stash, do not commit-on-behalf, do not auto-recover.

## Step 2: Verify the PR is merged

Look up the PR for `<FEATURE>`:

```bash
gh pr view --json state,number,url --jq '{state, number, url}'
```

If `gh` reports no PR for `<FEATURE>`, stop with:

> No PR found for `<FEATURE>`. Did you mean `/wf-ship` first?

If `state` is anything other than `MERGED`, stop with:

> PR for `<FEATURE>` is `<state>`, not `MERGED`. Merge it before wrapping.

Save `url` as `<PR_URL>` for the final report.

## Step 3: Resolve the Plane work item identifier

Best-effort, in this order:

1. **Conversation context** - scan the conversation for an explicit Plane identifier matching `\b[A-Z]{2,}-\d+\b`. The lexically most recent match wins.
2. **Branch name** - match `<FEATURE>` against `^([a-zA-Z]+)-(\d+)`. Uppercase the prefix and join it to the number (e.g. `dx-18-foo-bar` → `DX-18`).
3. If neither yields a candidate, set `<PLANE_ID>` to `none` and `<PLANE_OUTCOME>` to `not-inferred`.

The candidate is provisional at this point. Validation happens in Step 5. Once `<PLANE_ID>` is set, do not mutate it again - track what happened in `<PLANE_OUTCOME>` instead.

## Step 4: Switch to default and pull

```bash
git checkout <DEFAULT>
git pull --ff-only origin <DEFAULT>
```

If `git pull --ff-only` fails (diverged history), stop with the git error. Do not force, rebase, or reset.

## Step 5: Update Plane (only if `<PLANE_ID>` was resolved)

Skip this step entirely if `<PLANE_ID>` is `none` (Step 3 already set `<PLANE_OUTCOME>` to `not-inferred`). Otherwise:

1. Parse `<PLANE_ID>` into `project_identifier` (the alpha prefix) and `issue_identifier` (the integer suffix).
2. Call the Plane MCP tool `retrieve_work_item_by_identifier` with `project_identifier` and `issue_identifier`. If it returns 404 (or any not-found error), set `<PLANE_OUTCOME>` to `not-found` and skip the remaining sub-steps. The inferred `<PLANE_ID>` value is preserved for the report. This is not a fatal error.
3. From the response, save the work item's `id` field as the work item UUID and the `project` field as the project UUID.
4. Call `list_states` with `project_id` set to the project UUID. Find the state whose `group` is `"completed"`. If multiple match, prefer the one named `"Done"`. If no `completed` state exists, set `<PLANE_OUTCOME>` to `no-completed-state` and skip the remaining sub-steps.
5. Call `update_work_item` with `project_id` set to the project UUID, `work_item_id` set to the work item UUID, and `state` set to the completed state's UUID. Do not pass any other fields. On success, set `<PLANE_OUTCOME>` to `updated`.

If any Plane MCP call returns a non-404 error (network, auth, server), stop and report. The local feature branch still exists as a recovery point - fix Plane (e.g., update the work item state via the Plane UI), then manually run `git branch -D <FEATURE>` to finish.

## Step 6: Delete the local feature branch

```bash
git branch -D <FEATURE>
```

Use `-D` (uppercase) - squash and rebase merges aren't recognized by `git -d` even though `gh` confirmed the PR is merged.

## Step 7: Report

Print a single block:

```text
Wrapped up <FEATURE>:
- Switched to <DEFAULT> and pulled.
- Deleted local branch <FEATURE>.
- Marked <PLANE_ID> as Done.
- Closed PR: <PR_URL>
```

Switch on `<PLANE_OUTCOME>` for the third line of the block:

- `updated`: `- Marked <PLANE_ID> as Done.`
- `not-inferred`: `- No Plane work item updated - could not auto-infer one.`
- `not-found`: `- No Plane work item updated - <PLANE_ID> was inferred but not found in Plane.`
- `no-completed-state`: `- No Plane work item updated - project has no "completed" state.`

The user always sees whether Plane was touched and why.
