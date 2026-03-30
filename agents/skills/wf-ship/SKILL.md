---
name: wf-ship
description: Ship the current work for review - commit, push, create PR, and clean up. Use this skill whenever the user says "/wf-ship", "ship this", "send this for review", "ship it", or any variation of wanting to package up current work into a PR. Also trigger after a subagent finishes implementing a feature and the user wants to send it for review. Do NOT trigger for just committing (use /suggest-commit) or just creating a PR manually.
---

# Ship for Review

Package up the current work into a PR and clean up the local state. The behavior depends on which branch you're on.

## Step 0: Detect context

Run `git symbolic-ref --short HEAD` to get the current branch name.

Determine the default branch: check if `main` exists (`git rev-parse --verify main`), otherwise check `master`. Call this `<DEFAULT_BRANCH>` and save the name for use in later commands.

**If the current branch IS `<DEFAULT_BRANCH>`** - go to the "Shipping from default branch" flow.
**If the current branch is NOT `<DEFAULT_BRANCH>`** - go to the "Shipping from feature branch" flow.

---

## Shipping from default branch

You're on the default branch with unpushed commits that need to move to their own branch for a PR.

### 1. Safety checks

- Verify you're inside a git repo (`git rev-parse --is-inside-work-tree`).
- Verify `gh` is available.
- Verify the `origin` remote is configured: `git remote get-url origin`. If this fails, stop and tell the user no remote named `origin` is configured.
- Check for uncommitted changes with `git status --porcelain`. If there are unstaged or staged-but-uncommitted changes, stage and commit them first using the `suggest-commit` skill before proceeding.
- Verify the branch has an upstream (`git rev-parse --verify @{upstream}`).

### 2. Find unpushed commits

Fetch the latest remote state to ensure `@{upstream}` is current:

```bash
git fetch origin
```

Then list unpushed commits:

```bash
git log @{upstream}..HEAD --oneline
```

If there are no unpushed commits, tell the user there's nothing to ship and stop.

Save the upstream commit hash for later:

```bash
git rev-parse @{upstream}
```

### 3. Create a new branch

Generate a branch name. If a Linear ticket or issue number is known from conversation context, use it (e.g., `ENG-123-add-auth-flow`). Otherwise, generate a short descriptive name from the commit subjects - lowercase, hyphenated, under 50 chars (e.g., `add-dark-mode-toggle`).

Create the branch at the upstream point (not at HEAD):

```bash
git branch <branch-name> @{upstream}
```

### 4. Move commits to the new branch

Cherry-pick the unpushed commits onto the new branch. Use the upstream hash saved in Step 2 and the default branch name saved in Step 0:

```bash
git checkout <branch-name>
git cherry-pick <upstream-hash>..<DEFAULT_BRANCH>
```

If cherry-pick fails, tell the user about the conflict and stop. Do not force anything.

### 5. Push and create PR

```bash
git push -u origin <branch-name>
```

Create a PR with a proper summary (see "Writing the PR" section below). Capture the PR URL into a variable called `PR_URL` from the output of `gh pr create`. If `gh pr create` fails, stop immediately and report the error to the user - do NOT proceed to cleanup, do NOT delete the branch, do NOT reset the default branch.

### 6. Clean up

Only proceed here if PR creation succeeded and you have a PR URL.

Switch back to the default branch and reset it to its remote state:

```bash
git checkout <DEFAULT_BRANCH>
git reset --hard @{upstream}
```

Delete the local feature branch (it's been pushed, the remote copy is the source of truth):

```bash
git branch -D <branch-name>
```

### 7. Report

Display the PR URL and confirm the default branch has been reset. Copy it to the clipboard:

```bash
echo -n "$PR_URL" | pbcopy
```

(macOS only - skip this step on Linux)

---

## Shipping from feature branch

You're on a feature branch with work that's ready for review.

### 1. Safety checks

- Verify you're inside a git repo.
- Verify `gh` is available.
- Verify the `origin` remote is configured: `git remote get-url origin`. If this fails, stop and tell the user no remote named `origin` is configured.
- Determine `<DEFAULT_BRANCH>` as described above.

### 2. Stage and commit

Check `git status --porcelain`. If there are uncommitted changes (staged or unstaged), use the `suggest-commit` skill to craft a commit message, then stage and commit.

After committing (or if there was nothing to commit), check whether there are unpushed commits:

- If the branch has an upstream configured, run `git log @{upstream}..HEAD --oneline`. If this outputs nothing, there are no unpushed commits.
- If the branch has no upstream yet, there are commits to push by definition.

Only stop with "nothing to ship" if ALL of the following are true: nothing was committed AND the branch has an upstream AND there are no unpushed commits.

### 3. Push

```bash
git push -u origin HEAD
```

If the branch has no upstream yet, this sets it. If it already has one, it pushes new commits.

### 4. Create PR

Before running `gh pr create`, check if a PR already exists for this branch:

```bash
gh pr view --json url --jq .url 2>/dev/null
```

If a PR URL is returned, use that URL - do not create a new PR, skip to Step 5.

Otherwise, create a PR with a proper summary (see "Writing the PR" section below). Capture the PR URL into a variable called `PR_URL` from the output of `gh pr create`. If `gh pr create` fails, stop immediately and report the error to the user - do NOT proceed to cleanup, do NOT delete the branch.

### 5. Clean up

Only proceed here if a PR URL exists (either from an existing PR or newly created).

Switch back to the default branch:

```bash
git checkout <DEFAULT_BRANCH>
```

Delete the local feature branch:

```bash
git branch -D <branch-name>
```

### 6. Report

Display the PR URL and confirm the switch back to the default branch. Copy it to the clipboard:

```bash
echo -n "$PR_URL" | pbcopy
```

(macOS only - skip this step on Linux)

---

## Writing the PR

Use `gh pr create` with a title and body. Do NOT use `--fill`.

**Title:** Write in simple present imperative tense. The title should complete the sentence "This PR will..." Keep it under 70 characters. No conventional commit prefixes.

Good: `Add dark mode support to settings page`
Bad: `feat: add dark mode support` (prefix)
Bad: `Added dark mode` (past tense)

**Body:** Use this structure:

```
## Summary
<1-3 bullet points describing what changed and why>

## Test plan
<Bulleted checklist of how to verify the changes>
```

Derive the summary from the commit messages and the conversation context (what was discussed, what the subagent built, what was tested). The test plan should reflect what was actually verified during development.

Use a heredoc to pass the body:

```bash
gh pr create --title "the title" --body "$(cat <<'EOF'
## Summary
- bullet points here

## Test plan
- [ ] verification steps here
EOF
)"
```
