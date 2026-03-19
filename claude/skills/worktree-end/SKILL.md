---
name: worktree-end
description: Clean up a git worktree after feature work is done - validates state, optionally creates a PR, then removes the worktree and branch. Use this skill when the user says "/worktree-end", "end worktree", "finish worktree", "clean up worktree", "done with this worktree", "remove worktree", or wants to wrap up work in a worktree and return to the main repo. Also trigger when the user says "I'm done with this branch" or "merge this and clean up" while inside a worktree.
---

# Worktree End

Wind down a git worktree: verify everything is pushed, optionally create a PR, then remove the worktree and its branch.

## Prerequisites

Confirm the current directory is inside a git worktree (not the main working tree). Run:

```bash
git rev-parse --is-inside-work-tree && git worktree list
```

Parse the output of `git worktree list` to identify which entry matches the current directory. The main working tree is listed first - if the user is in that one, they're not in a worktree. Tell them this skill is meant to be run from inside a worktree created by `/worktree-start`, and stop.

While parsing, capture two things for later use:
- **The main repo path** (first entry in the worktree list)
- **The current worktree's branch name**

## Step 1: Check for uncommitted or unpushed work

This is a safety gate - the whole point is to prevent the user from accidentally losing work when the worktree is deleted.

Run these checks in order:

1. **Uncommitted changes**: `git status --porcelain`. If there's any output, the working tree has modifications or untracked files.
2. **Unpushed commits**: `git log @{upstream}.. --oneline 2>/dev/null`. If this produces output, there are local commits not yet pushed. If it errors (no upstream set), treat the entire branch as unpushed.

If either check finds something, report what was found clearly:
- For uncommitted changes: show the `git status --short` output
- For unpushed commits: show the `git log` output, or note that the branch has no upstream

Then tell the user to commit/push their work and run `/worktree-end` again when ready. Stop here - do not continue to Step 2.

## Step 2: Offer to create a PR

Everything is committed and pushed. Ask the user if they'd like to create a pull request for their branch before cleaning up.

Use AskUserQuestion with options:
- **Yes, create a PR** (Recommended) - create a PR into main using `gh pr create`
- **No, just clean up** - skip straight to removal

If they want a PR, create one using `gh pr create`. Follow the user's CLAUDE.md conventions for PR creation if any exist. After creation, display the PR URL.

If `gh` is not available or the push fails, show the error and let the user handle it manually. Still proceed to cleanup if they want.

## Step 3: Remove the worktree and branch

First, `cd` to the main repo path (captured during prerequisites).

Then remove the worktree and clean up the branch:

```bash
# cd to main repo (already done)
cd <main-repo-path>

# Remove the worktree
git worktree remove <worktree-path>

# Delete the local branch
git branch -d <branch-name>
```

Use `git branch -d` (lowercase) rather than `-D` so git will warn if the branch has unmerged changes. This is an extra safety net - if Step 1 passed correctly this shouldn't happen, but better safe than sorry.

If `git branch -d` fails because the branch isn't fully merged (e.g., the user skipped the PR), explain the situation and ask if they want to force-delete with `-D` or keep the branch around.

## Step 4: Confirm

Display a short summary:
- Worktree removed
- Branch deleted (or kept, if they chose to)
- PR link (if one was created)
- Current directory is now the main repo
