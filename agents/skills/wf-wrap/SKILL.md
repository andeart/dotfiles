---
name: wf-wrap
description: Wrap up work after a PR merges - mark the Plane work item Done, tear down the worktree if the work happened in one, switch back to the default branch, pull, and delete the merged feature branch. Use this skill whenever the user says "/wf-wrap", "wrap this up", "wrap up the merge", "post-merge cleanup", "switch back to main and clean up", or any variation of wanting to clean up after merging a PR. Do NOT trigger for shipping work for review (use /wf-ship) or for cleaning up older merged branches (use /wf-prune).
---

# Wrap Up After Merge

Run the post-merge cleanup sequence in one shot: mark the associated Plane work item as Done, get back to the default branch (tearing down the worktree if the work happened in one), pull, then delete the just-merged feature branch. Strong precondition checks; no confirmations once they pass.

Two facts shape the order below, and both are load-bearing:

- **Merges here are squashes.** The default branch gets a brand-new commit, so the feature branch tip is never an ancestor of it, and every ancestry test (`git merge-base --is-ancestor`, `git branch --merged`, `git branch -d`) reports fully-merged work as unmerged. Step 2 works around this once by comparing patch content; later steps inherit that result.
- **The work often happens in a linked worktree.** From inside one you cannot check out the default branch, and you cannot delete the branch you are standing on. So the worktree comes down before the pull, and the pull before the branch deletion.

## Step 0: Detect context

Determine the default branch: check if `main` exists (`git rev-parse --verify main 2>/dev/null`), otherwise check `master`. Call this `<DEFAULT>`.

Run `git symbolic-ref --short HEAD` to get the current branch. Save it as `<FEATURE>`. If the command fails, HEAD is detached - stop and tell the user to check out the feature branch first.

**If `<FEATURE>` IS `<DEFAULT>`**, stop immediately and tell the user:

> You're already on `<DEFAULT>` - nothing to wrap up. If you wanted to clean up older merged branches, use `/wf-prune`.

Then detect whether this is a linked worktree:

```bash
git rev-parse --git-dir          # linked: <primary>/.git/worktrees/<name>
git rev-parse --git-common-dir   # always: <primary>/.git
git rev-parse --show-toplevel    # this checkout's root
```

If the two git dirs differ, you are in a linked worktree. Set `<IN_WORKTREE>` to yes, save `<WORKTREE_PATH>` from `--show-toplevel`, and save `<PRIMARY>` as the directory containing `--git-common-dir`. Otherwise set `<IN_WORKTREE>` to no.

## Step 1: Safety checks

Fetch first so every check below reads current remote state:

```bash
git fetch origin
```

All of these must pass before any destructive action runs:

- Verify you're inside a git repo: `git rev-parse --is-inside-work-tree`.
- Verify `gh` is available on PATH.
- Verify the `origin` remote is configured: `git remote get-url origin`.
- Verify the working tree is clean: `git status --porcelain`. If it returns any output, stop with:

  > Uncommitted changes on `<FEATURE>` - handle them before wrapping.

- Verify nothing is unpushed:

  ```bash
  git rev-parse --verify --quiet @{upstream} >/dev/null && git log @{upstream}..HEAD --oneline
  ```

  Two distinct outcomes, and conflating them breaks the skill:

  - **Upstream resolves and the log prints commits** - stop and name them. They are not in the merge, so nothing below should discard them.
  - **The guard exits non-zero** - the upstream is gone. That is the normal state here, not a failure: merged PRs delete their head branch and any `--prune` fetch drops the tracking ref. Continue; Step 2 proves the same thing without the remote branch.

Any failure stops the skill immediately with a message naming the specific failure. Do not stash, do not commit-on-behalf, do not auto-recover.

## Step 2: Verify the PR is merged, and prove nothing is lost

Look up the PR for `<FEATURE>`:

```bash
gh pr view --json state,number,url --jq '{state, number, url}'
```

If `gh` reports no PR for `<FEATURE>`, stop with:

> No PR found for `<FEATURE>`. Did you mean `/wf-ship` first?

If `state` is anything other than `MERGED`, stop with:

> PR for `<FEATURE>` is `<state>`, not `MERGED`. Merge it before wrapping.

Save `url` as `<PR_URL>` for the final report.

`gh` reporting `MERGED` says the PR merged; it does not say the local branch holds nothing the default branch lacks. Prove that separately, because Step 5 may discard the branch:

```bash
mb=$(git merge-base origin/<DEFAULT> <FEATURE>)
git cherry origin/<DEFAULT> "$(git commit-tree "$(git rev-parse <FEATURE>^{tree})" -p "$mb" -m squash-probe)"
```

This squashes the branch's tree onto its own merge base and asks whether that patch is already upstream. One line comes back:

- `- <sha>` - an equivalent patch is on the default branch. The squash landed everything; discarding the branch loses nothing. Proceed.
- `+ <sha>` - it did not. Stop, show `git diff --stat $(git merge-base origin/<DEFAULT> <FEATURE>) <FEATURE>`, and say the branch holds content the default branch does not. Do not proceed.

The probe commit is dangling and gets garbage-collected; no ref moves. Do not substitute `git diff <FEATURE> origin/<DEFAULT>` - it looks equivalent, but reports a difference as soon as any unrelated commit lands on the default branch, blocking legitimate wraps and training you to override the one guard that matters.

## Step 3: Resolve the Plane work item identifier

Best-effort, in this order:

1. **Conversation context** - scan the conversation for an explicit Plane identifier matching `\b[A-Z]{2,}-\d+\b`. The lexically most recent match wins.
2. **Branch name** - strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)`. Uppercase the prefix and join it to the number (e.g. `worktree-zzz-0-echo-slice` → strip → `zzz-0-echo-slice` → `ZZZ-0`; `zzz-1-foo-bar` → `ZZZ-1`). `EnterWorktree` prefixes the branches it creates, and without the strip those branches match nothing at all.
3. If neither yields a candidate, set `<PLANE_ID>` to `none` and `<PLANE_OUTCOME>` to `not-inferred`.

Keep the examples above unresolvable. `ZZZ` is not a real project identifier and Plane numbers work items from 1, so neither can name a live item. Rule 1 scans the whole conversation, which includes this file once the skill loads, so a realistic-looking example here becomes a candidate for Step 4 to mark Done.

The candidate is provisional at this point. Validation happens in Step 4. Once `<PLANE_ID>` is set, do not mutate it again - track what happened in `<PLANE_OUTCOME>` instead.

## Step 4: Update Plane (only if `<PLANE_ID>` was resolved)

This runs **before** anything destructive, so a Plane failure leaves both the worktree and the branch intact as a recovery point.

Skip this step entirely if `<PLANE_ID>` is `none` (Step 3 already set `<PLANE_OUTCOME>` to `not-inferred`). Otherwise:

1. Parse `<PLANE_ID>` into `project_identifier` (the alpha prefix) and `issue_identifier` (the integer suffix).
2. Call the Plane MCP tool `retrieve_work_item_by_identifier` with `project_identifier` and `issue_identifier`. If it returns 404 (or any not-found error), set `<PLANE_OUTCOME>` to `not-found` and skip the remaining sub-steps. The inferred `<PLANE_ID>` value is preserved for the report. This is not a fatal error.
3. From the response, save the work item's `id` field as the work item UUID and the `project` field as the project UUID.
4. Call `list_states` with `project_id` set to the project UUID. Find the state whose `group` is `"completed"`. If multiple match, prefer the one named `"Done"`. If no `completed` state exists, set `<PLANE_OUTCOME>` to `no-completed-state` and skip the remaining sub-steps.
5. Call `update_work_item` with `project_id` set to the project UUID, `work_item_id` set to the work item UUID, and `state` set to the completed state's UUID. Do not pass any other fields. On success, set `<PLANE_OUTCOME>` to `updated`.

If any Plane MCP call returns a non-404 error (network, auth, server), stop and report. Nothing has been torn down yet - fix Plane (e.g. set the state in the UI), then re-run.

## Step 5: Get back to the default branch

### If `<IN_WORKTREE>` is no

```bash
git checkout <DEFAULT>
```

### If `<IN_WORKTREE>` is yes

Never `git checkout <DEFAULT>` from a linked worktree - git refuses, because the primary checkout already holds that branch. Tear the worktree down instead.

**Start with `ExitWorktree`, `action: "remove"`.** Three outcomes:

- **It removes the worktree and its branch.** Done, continue to the landing check.
- **It refuses, listing commits not on the original branch.** A squash merge guarantees this for every branch. Step 2 already proved the content is upstream, so re-invoke with `discard_changes: true`. **Never pass that flag without Step 2's `-` result in hand** - it is the one place in this skill where work can actually be lost.
- **It reports no active worktree session, or declines to remove this worktree.** It only manages worktrees it created this session; one made with `git worktree add`, one from an earlier session, or one entered by path is out of scope. Re-invoke with `action: "keep"` to restore the session's working directory before the directory disappears (harmless if that is a no-op too), then use the fallback.

**Fallback:**

```bash
cd <PRIMARY>
git worktree remove -f -f <WORKTREE_PATH>
```

Two `-f` flags, and both are required. `EnterWorktree` locks the worktrees it creates, and a single `--force` does not override a lock - it fails with `cannot remove a locked working tree`. The second `-f` is what overrides it. (`git worktree unlock <WORKTREE_PATH>` first also works, but errors on a worktree that isn't locked, which the non-`EnterWorktree` cases here are.)

The fallback removes the directory but not the branch; Step 7 handles that.

### Confirm where you landed

Neither path guarantees you land on `<DEFAULT>`. `ExitWorktree` restores the directory you started in, and the primary checkout sits on whatever branch it held when the worktree was created - often not `<DEFAULT>`, since `EnterWorktree` branches from `origin/<DEFAULT>` regardless of local HEAD.

```bash
git symbolic-ref --short HEAD
```

If that is not `<DEFAULT>`, run `git checkout <DEFAULT>` before continuing. Step 6 pulls into whatever branch is current, so skipping this check fast-forwards an unrelated branch onto the default branch.

## Step 6: Pull

```bash
git pull --ff-only origin <DEFAULT>
```

If `git pull --ff-only` fails (diverged history), stop with the git error. Do not force, rebase, or reset.

## Step 7: Delete the local feature branch

`ExitWorktree`'s `remove` deletes the branch along with the worktree, so it may already be gone. Treat "already gone" as success, but do not swallow a real failure:

```bash
if git show-ref --verify --quiet refs/heads/<FEATURE>; then git branch -D <FEATURE>; else echo "branch already deleted"; fi
```

Do not write this as `... && git branch -D <FEATURE> || true`. The `|| true` also masks `cannot delete branch '<FEATURE>' used by worktree at ...`, which means Step 5's teardown silently failed and the report would claim a cleanup that did not happen. If `git branch -D` errors, stop and show it.

Use `show-ref --verify refs/heads/...` rather than `git rev-parse --verify <FEATURE>`, which also matches a same-named tag. Use `-D` (uppercase) for the reason at the top of this skill: `git branch -d` does not recognize a squash merge, even though Step 2 proved the content landed.

## Step 8: Report

Print a single block:

```text
Wrapped up <FEATURE>:
- Marked <PLANE_ID> as Done.
- Removed the worktree at <WORKTREE_PATH>.
- Returned to <DEFAULT> and pulled.
- Deleted local branch <FEATURE>.
- Merged PR: <PR_URL>
```

When `<IN_WORKTREE>` was no, omit the worktree line and write `- Switched to <DEFAULT> and pulled.` instead.

Switch on `<PLANE_OUTCOME>` for the Plane line:

- `updated`: `- Marked <PLANE_ID> as Done.`
- `not-inferred`: `- No Plane work item updated - could not auto-infer one.`
- `not-found`: `- No Plane work item updated - <PLANE_ID> was inferred but not found in Plane.`
- `no-completed-state`: `- No Plane work item updated - project has no "completed" state.`

The user always sees whether Plane was touched and why.
