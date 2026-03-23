# Worktree Scripts Design

**Date:** 2026-03-22
**Status:** Approved

## Overview

Two standalone bash scripts in `git/bin/` that replace the `/worktree-start` and `/worktree-end` Claude skills with repeatable, argument-driven shell commands. Named `git-ws-start` and `git-ws-stop` to avoid collision with git's built-in `git worktree` subcommand.

## Scripts

### `git-ws-start`

**Usage:** `git ws-start [branch-name] [--base <branch>] [--dir <path>]`

**Branch name:**

- If provided, used as-is. Errors if the branch already exists in the repo.
- If omitted, auto-generates a name in the format `<adjective>-<noun>-<XX>` where `XX` is a 2-character uppercase alphanumeric suffix (e.g., `bright-falcon-3K`). Prompts the user to confirm with y/n before proceeding. Declining exits cleanly - re-run to get a new generated name.

**Base branch (`--base`):**

- Defaults to `main`. Falls back to `master` if `main` does not exist locally. Errors with a clear message if neither exists and no `--base` is provided.

**Worktree directory (`--dir`):**

- Defaults to `<repo-parent>/<repo-name>-worktrees/<branch-name>/`. For example, if the repo is at `~/code/my-project`, the default is `~/code/my-project-worktrees/bright-falcon-3K/`.
- If the `-worktrees` sibling directory does not exist yet, prompts the user y/n before creating it. Declining exits cleanly.
- A custom path can be passed via `--dir` to skip the default logic entirely.

**On success:**

Prints a polished confirmation message with the worktree path on its own line for easy double-click selection:

```
Worktree bright-falcon-3K is ready. Start working by running:

  cd /Users/you/code/my-project-worktrees/bright-falcon-3K
```

**Error cases:**

- Not inside a git repository
- Branch name already exists
- `--base` branch does not exist
- Worktree path already in use
- User declines directory creation prompt

---

### `git-ws-stop`

**Usage:** `git ws-stop <branch-name> [--pr]`

**Branch name:**

- Required. Errors if omitted.
- Errors if no worktree with that branch name is found in `git worktree list`.

**Context requirement:**

Must be run from the main working tree. Errors if:
- Not inside a git repository
- Run from inside a worktree (detected via `git worktree list` - current dir matches a non-primary entry)

**Safety gate:**

Before any cleanup, checks the target worktree for:

1. Uncommitted changes: `git -C <worktree-path> status --porcelain`
2. Unpushed commits: `git -C <worktree-path> log @{upstream}.. --oneline 2>/dev/null` (if no upstream set, the entire branch is treated as unpushed)

If either check finds anything, reports the details clearly and exits without touching the worktree.

**PR creation (`--pr`):**

- Runs `gh pr create` targeting the repo's default branch.
- Errors clearly if `gh` is not installed or not authenticated.
- Displays the PR URL on success.

**Cleanup:**

```bash
git worktree remove <worktree-path>
git branch -d <branch-name>
```

Uses `git branch -d` (not `-D`) - if git refuses due to unmerged changes, explains the situation and exits without force-deleting.

**On success:**

Prints a short confirmation:

```
Worktree bright-falcon-3K removed. Branch deleted.
```

Or with a PR:

```
PR created: https://github.com/you/repo/pull/42
Worktree bright-falcon-3K removed. Branch deleted.
```

**Error cases:**

- Branch name not provided
- No worktree found with that branch
- Run from inside a worktree
- Uncommitted changes or unpushed commits in target worktree
- `gh` not available (with `--pr`)
- Branch has unmerged changes (safe-delete refused)

## Implementation Notes

- **Two flat scripts, no shared library.** Matches the style of `git-lg` and `git-swo` in the same directory.
- **Word list embedded in `git-ws-start`.** ~50 adjectives and ~50 nouns hardcoded as bash arrays. Suffix is generated from the character set `[0-9A-Z]` using `$RANDOM`.
- **Scripts are executable** with `#!/usr/bin/env bash` and `set -e`.
- **README.md must be updated** to reflect the new files under `git/bin/` per the dotfiles repo conventions.
