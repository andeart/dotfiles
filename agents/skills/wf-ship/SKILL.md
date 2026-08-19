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
- Check for uncommitted changes with `git status --porcelain`. If there are unstaged or staged-but-uncommitted changes, use the `suggest-commit` skill to get a commit message, then immediately stage all changes and commit using that message.

  > **IMPORTANT: After suggest-commit returns, immediately continue executing wf-ship. Do NOT pause, display the message to the user, ask for confirmation, or wait for any input. The commit message is ready to use as-is. Resume the next step of wf-ship without interruption.**
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

Generate a branch name. If a work item is known for this change (see "Recording the work item" below), lead with its identifier (e.g., `ZZZ-0-add-auth-flow`). Otherwise, generate a short descriptive name from the commit subjects - lowercase, hyphenated, under 50 chars (e.g., `add-dark-mode-toggle`).

`ZZZ` is a placeholder, not a real project. Keep example identifiers in this file unresolvable.

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

### 6. Clean up the default branch

Reset the default branch back to the upstream point so it doesn't diverge from the remote. Since you're already on the feature branch, no checkout is needed:

```bash
git branch -f <DEFAULT_BRANCH> <upstream-hash>
```

This removes the local commit from the default branch now that it lives on the feature branch.

### 7. Link the PR to Plane

Follow the "Linking the PR to Plane" section below.

### 8. Report

Print the PR URL, then the Plane line from "Reporting the Plane outcome". You are now on the feature branch.

---

## Shipping from feature branch

You're on a feature branch with work that's ready for review.

### 1. Safety checks

- Verify you're inside a git repo.
- Verify `gh` is available.
- Verify the `origin` remote is configured: `git remote get-url origin`. If this fails, stop and tell the user no remote named `origin` is configured.
- Determine `<DEFAULT_BRANCH>` as described above.

### 2. Stage and commit

Check `git status --porcelain`. If there are uncommitted changes (staged or unstaged), use the `suggest-commit` skill to craft a commit message, then immediately stage all changes and commit using that message.

> **IMPORTANT: After suggest-commit returns, immediately continue executing wf-ship. Do NOT pause, display the message to the user, ask for confirmation, or wait for any input. The commit message is ready to use as-is. Resume the next step of wf-ship without interruption.**

After committing (or if there was nothing to commit), check whether there are unpushed commits:

- If the branch has an upstream configured, run `git log @{upstream}..HEAD --oneline`. If this outputs nothing, there are no unpushed commits.
- If the branch has no upstream yet, there are commits to push by definition.

If nothing was committed AND the branch has an upstream AND there are no unpushed commits, there is nothing new to push - which is not the same as nothing to do. Run Step 4's PR lookup now and branch on it:

- **A PR exists** - skip Step 3 entirely, then pick up Step 4 at its existing-PR branch: take `PR_URL` from the lookup, run the `--add-assignee @me` no-op, and continue into Step 5. The work item may still be missing its link: Plane can have been down on the ship that created the PR, the PR can predate the link step, or the link can have been removed by hand. Step 5 is the only thing that puts it back, and its duplicate check makes running it again free. Note that nothing was pushed, for the report.
- **No PR exists** - stop with "nothing to ship".

The default-branch flow's equivalent stop stays absolute. There, no unpushed commits means there is no work to move off the default branch at all - no feature branch and no PR for one - so there is nothing for a fall-through to act on.

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

If a PR URL is returned, use that URL - do not create a new PR. Assign it with `gh pr edit <PR_URL> --add-assignee @me`, which is a no-op if it's already assigned, then skip to Step 5.

Otherwise, create a PR with a proper summary (see "Writing the PR" section below). Capture the PR URL into a variable called `PR_URL` from the output of `gh pr create`. If `gh pr create` fails, stop immediately and report the error to the user - do NOT proceed to cleanup, do NOT delete the branch.

### 5. Link the PR to Plane

Follow the "Linking the PR to Plane" section below. Two paths reach here without having created anything - Step 2's fall-through when there was nothing to push, and Step 4's early exit when a PR already existed - and both land here on purpose. A branch that already has a PR still needs its link checked, and that section is what keeps a repeat run from adding a duplicate.

### 6. Report

Print the PR URL, then the Plane line from "Reporting the Plane outcome". You remain on the feature branch.

If Step 2 found nothing new to push, say so above the PR URL. A run that only checked the link should not read like one that shipped work.

---

## Writing the PR

Use `gh pr create` with a title, a body, and `--assignee @me`. Do NOT use `--fill`.

**Title:** Write in simple present imperative tense. The title should complete the sentence "This PR will..." Keep it under 70 characters. No conventional commit prefixes.

Good: `Add dark mode support to settings page`
Bad: `feat: add dark mode support` (prefix)
Bad: `Added dark mode` (past tense)

**Body:** Use this structure:

```markdown
Issue: [<ID>](https://app.plane.so/byanu/browse/<ID>/)

## Summary
<1-3 bullet points describing what changed and why>

## Test plan
<Bulleted checklist of how to verify the changes>
```

Derive the summary from the commit messages and the conversation context (what was discussed, what the subagent built, what was tested). The test plan should reflect what was actually verified during development.

### Assigning the PR

Pass `--assignee @me` so the PR lands on the shipper's plate instead of going out unowned. `@me` is whichever account `gh` is authenticated as in the calling repo, which is the identity that pushed the branch - do not try to derive a login from `git config user.email`, since private commit emails resolve to nothing.

Assignees need push access on the repo, so this fails on repos you contribute to from the outside. If `gh pr create` rejects the assignee, retry the same command without `--assignee` and tell the user the PR went up unassigned. Treat every other `gh pr create` failure as fatal per the flow above.

### Recording the work item

`Issue: [<ID>](https://app.plane.so/byanu/browse/<ID>/)` goes on the first line of the body, above `## Summary`. Link the identifier to its Plane work item - `byanu` is the only workspace, so hardcode it, and keep the trailing slash. Plane calls these work items, but the line stays `Issue:`. `/wf-wrap` reads it to decide which work item to mark Done once this merges, so a wrong identifier closes someone else's work.

Whatever this section resolves is also the work item that "Linking the PR to Plane" attaches the PR to. There is one identifier per ship and it is decided here.

Include the line only when one of these holds:

- The user named the work item for this change.
- The branch name leads with an identifier (e.g. `zzz-0-add-auth-flow` → `ZZZ-0`).

Otherwise omit it entirely - no placeholder, no `Issue: none`. Do not scan the conversation for identifier-shaped strings. They turn up in discussion, in skill examples, and in tool output for reasons that have nothing to do with this change, and nothing distinguishes those from a real assignment.

Use a heredoc to pass the body:

```bash
gh pr create --assignee @me --title "the title" --body "$(cat <<'EOF'
Issue: [ZZZ-0](https://app.plane.so/byanu/browse/ZZZ-0/)

## Summary
- bullet points here

## Test plan
- [ ] verification steps here
EOF
)"
```

Drop the `Issue:` line and the blank line after it when no work item is known.

---

## Linking the PR to Plane

With `PR_URL` in hand, attach it to the work item's Links sidebar so opening the work item shows the PR carrying it. Record the result in `<PLANE_OUTCOME>`; the Report step switches on it.

A link, not a comment: the sidebar holds one canonical entry that stays findable once the work item has a timeline, and listing those links is what makes the re-run check in sub-step 3 cheap.

### Which work item

Whichever identifier "Recording the work item" resolved. That is the only source.

- **No identifier there** - set `<PLANE_OUTCOME>` to `not-inferred` and skip the rest of this section. Do not re-derive a candidate and do not scan the conversation for one; the reasons in that section apply here unchanged.
- **The PR already existed** (feature-branch flow, via Step 2's fall-through or Step 4's early exit) - this run never composed a body, so read the identifier back off the PR that is already up:

  ```bash
  gh pr view --json body --jq '.body' | head -1
  ```

  Match `^Issue:\s*\[?([A-Z]+-\d+)\]?`. That is the same `Issue:` line, written by the earlier ship rather than this one, so it is not a new inference rule. No match means no identifier: `not-inferred`.

### Attaching it

1. Split the identifier into its alpha prefix and integer suffix (e.g. `ZZZ-0` → `ZZZ` and `0`).
2. Call the Plane MCP tool `workitem` with `action: "retrieve_by_identifier"` and `workitem_identifier` set to the full identifier. Save `id` from the response as the work item UUID and `project` as the project UUID. On a 404 or any not-found error, set `<PLANE_OUTCOME>` to `not-found` and stop - the identifier names nothing that exists, and reaching for a near miss would hang the PR off unrelated work.
3. Call `workitem_link` with `action: "list"`, `project_id`, and `workitem_id`. If any result's `url` already equals `PR_URL` ignoring a trailing slash, set `<PLANE_OUTCOME>` to `already-linked` and stop. Plane does not reject a duplicate URL, so this check is the only thing standing between a re-ship and two identical entries in the sidebar.
4. Call `workitem_link` with `action: "create"`, `project_id`, `workitem_id`, and `url` set to `PR_URL`. On success set `<PLANE_OUTCOME>` to `linked`.

`ZZZ` is a placeholder, not a real project. Keep example identifiers in this file unresolvable.

### When Plane is unreachable

**A Plane failure never fails the ship.** By the time this section runs the branch is pushed and the PR exists - there is nothing to roll back, and stopping here strands the user mid-flow with no report of work that already went out. On any error other than the not-found handled above (network, auth, server), set `<PLANE_OUTCOME>` to `failed`, keep the error text, and continue to the Report step. Do not retry and do not fall back to posting a comment instead.

### Reporting the Plane outcome

The Report step prints the PR URL, then one line for `<PLANE_OUTCOME>`:

- `linked`: `- Linked the PR on <ID>.`
- `already-linked`: `- <ID> already links this PR - left as is.`
- `not-inferred`: `- No Plane work item linked - none known for this change.`
- `not-found`: `- No Plane work item linked - <ID> was not found in Plane.`
- `failed`: `- No Plane work item linked - Plane returned: <error>. The PR is up; add the link by hand if you want it.`

The user always sees whether Plane was touched, and why not when it wasn't.
