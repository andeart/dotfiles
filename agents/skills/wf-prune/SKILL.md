---
name: wf-prune
description: Clean up local branches that have already been merged into the default branch. Use this skill whenever the user says "/wf-prune", "clean up branches", "prune branches", "delete merged branches", "tidy up branches", or any variation of wanting to remove local branches whose work has already landed. Also trigger after shipping multiple PRs when the user wants to clean up their local state.
---

# Prune Merged Branches

Remove local branches that have been merged into the default branch, with full visibility into what's being cleaned up.

## Step 0: Detect context

Determine the default branch: check if `main` exists (`git rev-parse --verify main 2>/dev/null`), otherwise check `master`. Call this `<DEFAULT>`.

Run `git symbolic-ref --short HEAD` to get the current branch.

**If you are NOT on `<DEFAULT>`**, stop immediately and tell the user:

> You're on `<current-branch>`, not `<DEFAULT>`. Switch to `<DEFAULT>` first - this skill only runs from the default branch to avoid accidentally deleting the branch you're working on.

Do not proceed further.

## Step 1: Pull latest

```bash
git fetch --prune origin
git pull --ff-only origin <DEFAULT>
```

Use `--prune` so stale remote tracking refs get cleaned up. If the pull fails (e.g. diverged history), stop and tell the user. Do not force anything.

## Step 2: Find merged branches

A branch counts as "merged" if **either** of these is true:

1. **Git ancestry** - `git branch --merged <DEFAULT>` lists it (works for true merge commits)
2. **GitHub PR** - `gh pr list --head <branch-name> --state merged` returns a result (works for squash and rebase merges)

First, get all local branches except `<DEFAULT>` (and `master`/`main` if the other exists). Then check each one against both criteria. A branch only needs to satisfy one to be considered merged.

For criterion 1:
```bash
git branch --merged <DEFAULT>
```

For any branches NOT caught by criterion 1, check criterion 2:
```bash
gh pr list --head <branch-name> --state merged --json number --jq 'length'
```

If neither criterion matches a branch, it is not merged - exclude it.

If no merged branches are found, tell the user everything is clean and stop.

## Step 3: Gather PR and remote info

For each merged branch, collect two things:

**PR info** - look up the PR that merged it:

```bash
gh pr list --head <branch-name> --state merged --json number,title,url --jq '.[0]'
```

If no PR is found via `--head`, show "no obvious PR found."

**Remote status** - check whether the remote counterpart still exists:

```bash
git ls-remote --heads origin <branch-name>
```

If the remote branch still exists, also check if it has commits the local branch doesn't:

```bash
git log <branch-name>..origin/<branch-name> --oneline 2>/dev/null
```

Present everything in a single consolidated list. Each line should show the branch name, its PR (if any), and its remote status:

```
Merged branches:
- feature-xyz - PR #42: "Add xyz support" (https://github.com/...) - remote deleted
- fix-abc - PR #18: "Fix abc bug" (https://github.com/...) - remote exists (in sync)
- quick-patch - merged via git ancestry, no PR found - remote deleted
```

Do NOT suggest deleting remote branches. That's not this skill's job.

## Step 5: Offer to delete

All branches from Step 2 are confirmed merged (via git ancestry or a merged GitHub PR). Present them all and ask the user for confirmation:

> These branches are merged. Ready to delete them locally?
> - branch-a
> - branch-b

Also note their remote status from Step 3 so the user has full context, but remote status does not change whether a branch is eligible - the merge evidence is what matters.

Wait for explicit confirmation. If the user confirms, delete each one:

```bash
git branch -D <branch-name>
```

Use `-D` (uppercase) because squash-merged and rebase-merged branches won't be recognized as merged by git's `-d` check, even though we've independently confirmed they are merged.

After deletion, confirm what was removed.
