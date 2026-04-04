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
git fetch origin
git pull --ff-only origin <DEFAULT>
```

If the pull fails (e.g. diverged history), stop and tell the user. Do not force anything.

## Step 2: Find merged branches

List local branches whose commits have all been incorporated into `<DEFAULT>`:

```bash
git branch --merged <DEFAULT>
```

Filter out `<DEFAULT>` itself (and `master`/`main` if the other exists). The remaining branches are candidates for cleanup.

If none are found, tell the user everything is clean and stop.

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
- quick-patch - no obvious PR found - remote exists (1 commit ahead of local)
```

Do NOT suggest deleting remote branches. That's not this skill's job.

## Step 5: Offer to delete

Separate the branches into two groups:

1. **Safe to delete** - merged into `<DEFAULT>` AND remote branch is gone (or never existed)
2. **Remote still exists** - merged but remote counterpart is still present

If there are branches in group 2, mention them but explain you won't offer to delete those since their remote counterparts still exist - the user should clean those up through GitHub (or the remote) first.

For group 1 (if any), ask the user:

> These branches are merged and their remote counterparts are gone. Ready to delete them locally?
> - branch-a
> - branch-b

Wait for explicit confirmation. If the user confirms, delete each one:

```bash
git branch -d <branch-name>
```

Use `-d` (lowercase), not `-D`. Since these branches are confirmed merged, `-d` will succeed. If it somehow fails for a branch, report the error and continue with the rest.

After deletion, confirm what was removed.
