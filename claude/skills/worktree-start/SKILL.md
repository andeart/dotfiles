---
name: worktree-start
description: Create a new git worktree for feature work with interactive setup. Use this skill when the user says "/worktree-start", "start a worktree", "create a worktree", "new worktree", or wants to begin isolated feature work in a separate working directory. Also trigger when the user says they want to "work on a feature in isolation" or "set up a branch to work on separately".
---

# Worktree Start

Create a new git worktree interactively, walking the user through location, base branch, and naming.

## Prerequisites

Before starting, verify the current directory is a git repository. If not, tell the user and stop.

## Step 1: Choose worktree location

Ask the user where to create the worktree. Compute the three options dynamically based on the current repo:

- **Sibling directory**: Take the repo's directory name and append `-worktrees`. For example, if working in `~/code/my-project`, suggest `~/code/my-project-worktrees/<worktree-name>/`. This keeps worktrees organized outside the repo without cluttering the repo itself.
- **In-repo**: Place it inside the repo at `.worktrees/<worktree-name>/`. Add `.worktrees` to `.gitignore` if it isn't already there.
- **Custom path**: Let the user type their own path.

Use AskUserQuestion with the actual computed paths as option labels so the user sees exactly where things will go (use `<worktree-name>` as a placeholder for the name they haven't chosen yet).

## Step 2: Choose base branch

Ask the user which branch to base the worktree on. Offer:

- **main** (or **master**, whichever exists) as the recommended default
- **Current branch** (show its name) if different from main/master
- **Custom** to let them type a branch name

If the repo only has one branch, skip this question and use it automatically.

## Step 3: Choose worktree name

The worktree name doubles as the new branch name. Ask the user to pick:

- **Random name**: Generate a short, memorable name using the pattern `<adjective>-<noun>` (e.g., `bright-falcon`, `swift-river`, `calm-reef`). Show the generated name so they can accept or regenerate.
- **Custom name**: Let the user type their own name.

Validate that the branch name doesn't already exist. If it does, tell the user and ask for a different name.

## Step 4: Create the worktree

Run the git commands to create the worktree:

```bash
# Create parent directory if needed
mkdir -p <parent-directory>

# Create the worktree with a new branch based on the chosen base
git worktree add -b <branch-name> <worktree-path> <base-branch>
```

If the creation fails, show the error and suggest fixes (e.g., branch already exists, path already in use).

## Step 5: Confirm and hand off

After successful creation, display:
- The full path to the new worktree
- The branch name
- The base branch it was created from
- A reminder that they can use `/worktree-end` when they're done
- A ready-to-copy command to start a Claude session in the worktree: `cd <worktree-path> && claude`

Copy this command to the clipboard automatically using `pbcopy`.
