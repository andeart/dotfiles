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
