# `wf-ship` Skill Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create a `/wf-ship` skill that automates the post-implementation workflow - committing, pushing, creating a PR, and cleaning up - so a developer can ship work for review in one command.

**Architecture:** Single SKILL.md file that instructs Claude to detect whether it's on a default branch or feature branch, then runs the appropriate shipping flow. On the default branch, it picks up unpushed commits into a new branch (like `git wt-pickup`). On a feature branch, it commits staged/unstaged changes, pushes, creates a PR, and switches back to the default branch with cleanup.

**Tech Stack:** Git, GitHub CLI (`gh`), existing `suggest-commit` skill

---

### Task 1: Create the skill file

**Files:**
- Create: `agents/skills/wf-ship/SKILL.md`

- [ ] **Step 1: Create the skill directory**

```bash
mkdir -p /Users/anuragdevanapally/code/dotfiles/agents/skills/wf-ship
```

- [ ] **Step 2: Write SKILL.md**

Create `agents/skills/wf-ship/SKILL.md` with the content below. This is the complete skill - no other files needed.

````markdown
---
name: wf-ship
description: Ship the current work for review - commit, push, create PR, and clean up. Use this skill whenever the user says "/wf-ship", "ship this", "send this for review", "ship it", or any variation of wanting to package up current work into a PR. Also trigger after a subagent finishes implementing a feature and the user wants to send it for review. Do NOT trigger for just committing (use /suggest-commit) or just creating a PR manually.
---

# Ship for Review

Package up the current work into a PR and clean up the local state. The behavior depends on which branch you're on.

## Step 0: Detect context

Run `git symbolic-ref --short HEAD` to get the current branch name.

Determine the default branch: check if `main` exists (`git rev-parse --verify main`), otherwise check `master`. Call this `DEFAULT_BRANCH`.

**If the current branch IS the default branch** - go to the "Shipping from default branch" flow.
**If the current branch is NOT the default branch** - go to the "Shipping from feature branch" flow.

---

## Shipping from default branch

You're on the default branch with unpushed commits that need to move to their own branch for a PR.

### 1. Safety checks

- Verify you're inside a git repo (`git rev-parse --is-inside-work-tree`).
- Verify `gh` is available.
- Check for uncommitted changes with `git status --porcelain`. If there are unstaged or staged-but-uncommitted changes, stage and commit them first using the `suggest-commit` skill before proceeding.
- Verify the branch has an upstream (`git rev-parse --verify @{upstream}`).

### 2. Find unpushed commits

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

Cherry-pick the unpushed commits onto the new branch:

```bash
git checkout <branch-name>
git cherry-pick @{upstream}..DEFAULT_BRANCH
```

If cherry-pick fails, tell the user about the conflict and stop. Do not force anything.

### 5. Push and create PR

```bash
git push -u origin <branch-name>
```

Create a PR with a proper summary (see "Writing the PR" section below).

### 6. Clean up

Switch back to the default branch and reset it to its remote state:

```bash
git checkout DEFAULT_BRANCH
git reset --hard @{upstream}
```

Delete the local feature branch (it's been pushed, the remote copy is the source of truth):

```bash
git branch -D <branch-name>
```

### 7. Report

Display the PR URL and confirm the default branch has been reset. Copy the PR URL to the clipboard:

```bash
echo -n "PR_URL" | pbcopy
```

---

## Shipping from feature branch

You're on a feature branch with work that's ready for review.

### 1. Safety checks

- Verify you're inside a git repo.
- Verify `gh` is available.
- Determine `DEFAULT_BRANCH` as described above.

### 2. Stage and commit

Check `git status --porcelain`. If there are uncommitted changes (staged or unstaged), use the `suggest-commit` skill to craft a commit message, then stage and commit.

If there's nothing to commit and nothing to push, tell the user there's nothing to ship and stop.

### 3. Push

```bash
git push -u origin HEAD
```

If the branch has no upstream yet, this sets it. If it already has one, it pushes new commits.

### 4. Create PR

Create a PR with a proper summary (see "Writing the PR" section below).

### 5. Clean up

Switch back to the default branch:

```bash
git checkout DEFAULT_BRANCH
```

Delete the local feature branch:

```bash
git branch -D <branch-name>
```

### 6. Report

Display the PR URL and confirm the switch back to the default branch. Copy the PR URL to the clipboard:

```bash
echo -n "PR_URL" | pbcopy
```

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
````

- [ ] **Step 3: Verify the file is valid**

Read back the created file to confirm frontmatter parses correctly and content is complete.

---

### Task 2: Update README structure tree

**Files:**
- Modify: `README.md:62` (inside the `agents/` section of the structure tree)

- [ ] **Step 1: Add wf-ship to the structure tree**

The `skills/*` entry in the README structure tree uses a wildcard, so new skill directories are already covered. Verify this by reading the relevant section - if `skills/*` is listed, no change is needed.

- [ ] **Step 2: Commit**

Stage and commit the new skill file:

```bash
git add agents/skills/wf-ship/SKILL.md
git commit -m "Add wf-ship skill for shipping work to PR"
```
