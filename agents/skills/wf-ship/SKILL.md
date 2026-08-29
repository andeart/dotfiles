---
name: wf-ship
description: Ship the current work for review - commit, push, create PR, and clean up. Use this skill whenever the user says "/wf-ship", "ship this", "send this for review", "ship it", or any variation of wanting to package up current work into a PR. Also trigger after a subagent finishes implementing a feature and the user wants to send it for review. Do NOT trigger for just committing (use /suggest-commit) or just creating a PR manually.
---

# Ship for Review

Package up the current work into a PR and clean up the local state. The behavior depends on which branch you're on.

## Output

Happy-path steps produce no progress output. Do not announce a step, do not confirm that a check passed, do not restate what a command returned, and do not summarize what a section proved. On a successful run the Report step is the only thing the user sees.

The one exception: a step that does something a reader would otherwise be surprised by gets a single short line naming what is happening and why - for example "Switching to the feature branch because the commits belong there." One line, not a paragraph, and only where the surprise is real.

Everything else still reports in full. Every stop condition below, every failure, and every piece of work that was skipped rather than done gets the whole message it defines. Silence on the happy path is what makes the output that does appear worth reading.

## Step 0: Detect context and run the safety checks

One call answers everything both flows need to know. Run it as a single command - the individual checks are cheap, but each separate call costs a round-trip:

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'repo=no'; exit 0; }
echo 'repo=yes'
command -v gh >/dev/null 2>&1 && echo 'gh=yes' || echo 'gh=no'
origin=$(git remote get-url origin 2>/dev/null)
echo "origin=$origin"
[ -n "$origin" ] && git fetch --quiet origin
echo "branch=$(git symbolic-ref --short HEAD 2>/dev/null)"
default=$(git rev-parse --verify --quiet main >/dev/null && echo main || { git rev-parse --verify --quiet master >/dev/null && echo master; })
echo "default=$default"
echo "upstream=$(git rev-parse --verify --quiet '@{upstream}')"
echo 'status<<<'
git status --porcelain
```

The fetch runs before the `@{upstream}` read so the upstream hash and every later `@{upstream}..HEAD` comparison reflect current remote state. Everything after the `status<<<` marker is porcelain output; no output there means a clean tree.

Read the results into the names the rest of this skill uses:

- `repo=no` - stop and tell the user this isn't a git repository. Nothing else in the output is meaningful.
- `gh=no` - stop and tell the user `gh` is not on PATH.
- `origin=` empty - stop and tell the user no remote named `origin` is configured.
- `branch=` empty - HEAD is detached. Stop and tell the user to check out a branch first.
- `default=` - this is `<DEFAULT_BRANCH>`. If it is empty, neither `main` nor `master` exists; stop and say so.
- `upstream=` - the upstream commit hash, or empty if the branch has no upstream. This is the hash the default-branch flow's Step 2 needs; do not re-read it.
- `status<<<` - the porcelain lines, if any.

### Resolve the wf config

One call, and every section below reads its output. Calling it per section would fork `yq` several times for one file that does not change mid-run:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
```

Save the whole dump as `<WF_CONFIG>`. The keys this skill reads:

- `ship.draft-by-default` - whether "Writing the PR" passes `--draft`.
- `ship.test-commands.N` - what "Running the tests" runs. Absent means run nothing.
- `states.shaping`, `states.implementing`, `states.in-review` - the names "Reconciling the Plane state" matches against.

Exit 3 means the repo's `.wf.yml` is present but wrong. Stop and print stderr: a broken config is the user's to fix, and guessing a draft setting would ship a PR in the wrong state. Exit 2 with `yq` missing is the same - say what is missing rather than proceeding on defaults.

**If the skill was invoked as `/wf-ship ready`** - go to the "Finalizing a draft" flow. That flow pushes nothing and creates nothing; it flips an existing draft and reconciles the work item.

The mode is the literal argument `ready`, never inferred. Inferring it from a PR's draft status would flip every draft the moment its branch was shipped again, which is the opposite of what a draft is for.

Then route:

**If `branch` IS `<DEFAULT_BRANCH>`** - go to the "Shipping from default branch" flow.
**If `branch` is NOT `<DEFAULT_BRANCH>`** - go to the "Shipping from feature branch" flow.

---

## Shipping from default branch

You're on the default branch with unpushed commits that need to move to their own branch for a PR.

### 1. Commit anything outstanding

Step 0 already ran every safety check for this flow. If it reported porcelain lines, use the `suggest-commit` skill to get a commit message, then immediately stage all changes and commit using that message.

> **IMPORTANT: After suggest-commit returns, immediately continue executing wf-ship. Do NOT pause, display the message to the user, ask for confirmation, or wait for any input. The commit message is ready to use as-is. Resume the next step of wf-ship without interruption.**

If `upstream` was empty, this branch has no upstream. Stop and tell the user.

### 2. Find unpushed commits

Step 0 already fetched, so `@{upstream}` is current, and its hash is the `upstream` value from that output. List what has not been pushed:

```bash
git log @{upstream}..HEAD --oneline
```

If there are no unpushed commits, tell the user there's nothing to ship and stop.

### 3. Create a new branch

Generate a branch name. If a work item is known for this change (see "Recording the work item" below), lead with its identifier (e.g., `ZZZ-0-add-auth-flow`). Otherwise, generate a short descriptive name from the commit subjects - lowercase, hyphenated, under 50 chars (e.g., `add-dark-mode-toggle`).

`ZZZ` is a placeholder, not a real project. Keep example identifiers in this file unresolvable.

Create the branch at the upstream point (not at HEAD):

```bash
git branch <branch-name> @{upstream}
```

### 4. Move commits to the new branch

Cherry-pick the unpushed commits onto the new branch. Use the `upstream` hash from Step 0 and the default branch name from Step 0:

```bash
git checkout <branch-name>
git cherry-pick <upstream-hash>..<DEFAULT_BRANCH>
```

If cherry-pick fails, tell the user about the conflict and stop. Do not force anything.

Record what this push carries, before pushing - afterwards the upstream has moved and the range is empty. The new branch has no upstream of its own yet, so this compares against the point it was cut from:

```bash
git diff --name-only <upstream-hash>..HEAD
```

Save the file list as `<PUSHED_PATHS>`.

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

### 7. Link the PR to Plane and reconcile its state

Follow the "Linking the PR to Plane" section below, then "Reconciling the Plane state".

### 8. Report

Print the PR URL, then the Plane line from "Reporting the Plane outcome", then the state line from "Reporting it". You are now on the feature branch.

---

## Finalizing a draft

You were invoked as `/wf-ship ready`. Nothing is committed, pushed or created here.

### 1. Find the PR

```bash
gh pr view --json url,number,isDraft,body --jq '.url, .number, .isDraft, "body<<<", (.body // "" | split("\n")[0])'
```

- **No PR for this branch** - stop with:

  > No pull request exists for `branch`. Run `/wf-ship` first to open one.

- **`isDraft` is `false`** - the PR is already ready. Say so, skip Step 2, and continue to Step 3: the work item may still be sitting in the wrong state, and reconciling it is the rest of this flow's job.

Save the URL as `PR_URL` and the body's first line as `<PR_FIRST_LINE>`.

### 2. Flip it

```bash
gh pr ready <PR_URL>
```

If this fails, stop and report. Do not continue to the state write - a work item saying In Review over a PR still marked draft is worse than one left alone.

### 3. Reconcile and report

Set `<PR_STATE>` to `ready`, then follow "Reconciling the Plane state" and "Linking the PR to Plane". Report the PR URL, whether it was flipped or already ready, and the Plane lines from both sections.

---

## Shipping from feature branch

You're on a feature branch with work that's ready for review.

### 1. Stage and commit

Step 0 already ran every safety check for this flow and resolved `<DEFAULT_BRANCH>`. If it reported porcelain lines, use the `suggest-commit` skill to craft a commit message, then immediately stage all changes and commit using that message.

> **IMPORTANT: After suggest-commit returns, immediately continue executing wf-ship. Do NOT pause, display the message to the user, ask for confirmation, or wait for any input. The commit message is ready to use as-is. Resume the next step of wf-ship without interruption.**

After committing (or if there was nothing to commit), check whether there are unpushed commits:

- If Step 0 reported a non-empty `upstream`, run `git log @{upstream}..HEAD --oneline`. If this outputs nothing, there are no unpushed commits.
- If `upstream` was empty, the branch has no upstream yet, so there are commits to push by definition.

If nothing was committed AND the branch has an upstream AND there are no unpushed commits, there is nothing new to push - which is not the same as nothing to do. Run Step 3's PR lookup now and branch on it:

- **A PR exists** - skip Step 2 entirely, then pick up Step 3 at its existing-PR branch: take `PR_URL` from the lookup, run the `--add-assignee @me` no-op, and continue into Step 4. The work item may still be missing its link: Plane can have been down on the ship that created the PR, the PR can predate the link step, or the link can have been removed by hand. Step 4 is the only thing that puts it back, and its duplicate check makes running it again free. Note that nothing was pushed, for the report.
- **No PR exists** - stop with "nothing to ship".

The default-branch flow's equivalent stop stays absolute. There, no unpushed commits means there is no work to move off the default branch at all - no feature branch and no PR for one - so there is nothing for a fall-through to act on.

### 2. Push

Record what this push carries, before pushing - afterwards the upstream has moved and the range is empty:

```bash
git rev-parse --verify --quiet '@{upstream}' >/dev/null 2>&1 \
  && git diff --name-only '@{upstream}'..HEAD \
  || git diff --name-only "origin/<DEFAULT_BRANCH>"..HEAD
```

Save the file list as `<PUSHED_PATHS>`. A branch with no upstream has never been pushed, so its whole divergence from the default branch is what is going up.

```bash
git push -u origin HEAD
```

If the branch has no upstream yet, this sets it. If it already has one, it pushes new commits.

### 3. Create PR

Before running `gh pr create`, check whether a PR already exists for this branch. Read the URL and the body's first line together - the Plane section below needs that line, and `gh` is network-bound, so a second lookup is the most expensive duplicate this skill can make:

```bash
gh pr view --json url,body --jq '.url, (.body // "" | split("\n")[0])' 2>/dev/null
```

Two lines come back: the PR URL, then the first line of its body. If a PR URL is returned, use it - do not create a new PR. Save the body's first line as `<PR_FIRST_LINE>` for "Linking the PR to Plane". Assign it with `gh pr edit <PR_URL> --add-assignee @me`, which is a no-op if it's already assigned, then skip to Step 4.

Otherwise, create a PR with a proper summary (see "Writing the PR" section below). Capture the PR URL into a variable called `PR_URL` from the output of `gh pr create`. If `gh pr create` fails, stop immediately and report the error to the user - do NOT proceed to cleanup, do NOT delete the branch.

### 4. Link the PR to Plane and reconcile its state

Follow the "Linking the PR to Plane" section below. Two paths reach here without having created anything - Step 1's fall-through when there was nothing to push, and Step 3's early exit when a PR already existed - and both land here on purpose. A branch that already has a PR still needs its link checked, and that section is what keeps a repeat run from adding a duplicate.

Then follow "Reconciling the Plane state".

### 5. Report

Print the PR URL, then the Plane line from "Reporting the Plane outcome", then the state line from "Reporting it". You remain on the feature branch.

If Step 1 found nothing new to push, say so above the PR URL. A run that only checked the link should not read like one that shipped work.

---

## Writing the PR

Use `gh pr create` with a title, a body, and `--assignee @me`. Do NOT use `--fill`.

Pass `--draft` when `<WF_CONFIG>`'s `ship.draft-by-default` is `true`. A draft is the default because the stage a PR is in is what `/wf-ship ready` later reads to move the work item to In Review - without the draft-then-ready split there is no event that distinguishes an initial push from a finalize. Set the key `false` in a repo where drafts are not wanted; nothing else in this skill changes.

**Title:** Lead with the work item identifier and a colon when one is known, then the subject. The identifier is whatever "Recording the work item" resolves - there is one per ship and it is decided there. When it resolves nothing, the title starts at the verb; no placeholder, and no bare colon.

The identifier leads rather than trails because a subject that runs long is truncated from the right, in `git log --oneline` and in GitHub's commit list alike. A trailing identifier is the first thing to disappear, and it takes the `(#123)` with it.

Write the subject in simple present imperative tense; it should complete the sentence "This PR will..." Keep the subject under 70 characters - the identifier does not count against that. No conventional commit prefixes: the identifier names one work item rather than classifying the change, and carrying it does not license a `feat:` alongside.

Good: `ZZZ-0: Add dark mode support to settings page`
Good: `Add dark mode support to settings page` (no work item known)
Bad: `feat: add dark mode support` (prefix)
Bad: `ZZZ-0: feat: add dark mode support` (an identifier is not a licence for a type prefix)
Bad: `Add dark mode support to settings page (ZZZ-0)` (identifier leads, never trails)
Bad: `Added dark mode` (past tense)

**Body:** Use this structure:

```markdown
Issue: [<ID>](https://app.plane.so/<workspace>/browse/<ID>/)

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

`Issue: [<ID>](https://app.plane.so/<workspace>/browse/<ID>/)` goes on the first line of the body, above `## Summary`. Link the identifier to its Plane work item, and keep the trailing slash. `<workspace>` comes from "Resolving the workspace" below - never hardcode a slug. Plane calls these work items, but the line stays `Issue:`. `/wf-wrap` reads it to decide which work item to mark Done once this merges, so a wrong identifier closes someone else's work.

Whatever this section resolves is also the work item that "Linking the PR to Plane" attaches the PR to. There is one identifier per ship and it is decided here.

Include the line only when one of these holds:

- The user named the work item for this change.
- The branch name leads with an identifier (e.g. `zzz-0-add-auth-flow` → `ZZZ-0`).

Otherwise omit it entirely - no placeholder, no `Issue: none`. Do not scan the conversation for identifier-shaped strings. They turn up in discussion, in skill examples, and in tool output for reasons that have nothing to do with this change, and nothing distinguishes those from a real assignment.

### Resolving the workspace

Only when the `Issue:` line is going in. No identifier means no link, and nothing to resolve.

The workspace is the slug in `app.plane.so/<workspace>/...`. Read it from the `workspace` key in `.workitems.plane.yml` - repo root first, then `tmp/.workitems.plane.yml`, and the root file wins if both exist. This is the same config the work item skills read; `work-item-conventions/references/plane.md` documents the full key set.

A repo still carrying the old `.plane.yml` name is not read here, deliberately - `migrate-work-item-config` is what converts it. Treat that repo as having no workspace configured and follow the ask below, then mention the migration rather than reaching into the old file.

If the key is set, use it. If it is missing, empty, or still commented out, ask for it in one line:

> No Plane workspace is configured. What's the workspace slug - the part after `app.plane.so/`?

With the answer in hand:

- **A `.workitems.plane.yml` exists** - offer to store the slug in it, and write only on a yes. Uncomment the `workspace:` line if the file carries one commented out; otherwise append `workspace: <slug>`.
- **No `.workitems.plane.yml` exists** - offer to create one in the repo root holding just that key. `file-work-item` appends the rest the next time it runs.
- **The user declines the offer** - use the slug for this ship and move on. Do not ask twice in one run.

If the user declines to name a slug at all, write the line bare - `Issue: <ID>`, no markdown link. `/wf-wrap` matches that form too, so the wrap still finds the work item and only the convenience link is lost.

Use a heredoc to pass the body:

```bash
gh pr create --draft --assignee @me --title "ZZZ-0: the title" --body "$(cat <<'EOF'
Issue: [ZZZ-0](https://app.plane.so/<workspace>/browse/ZZZ-0/)

## Summary
- bullet points here

## Test plan
- [ ] verification steps here
EOF
)"
```

Drop `--draft` when the key is `false`.

Drop the `Issue:` line and the blank line after it when no work item is known.

Set `<PR_STATE>` to `draft` or `ready` to match what was created. "Reconciling the Plane state" reads it, and the Report step names it so a run that opened a draft does not read like one that opened a finished PR.

---

## Linking the PR to Plane

With `PR_URL` in hand, attach it to the work item's Links sidebar so opening the work item shows the PR carrying it. Record the result in `<PLANE_OUTCOME>`; the Report step switches on it.

A link, not a comment: the sidebar holds one canonical entry that stays findable once the work item has a timeline, and listing those links is what makes the re-run check in sub-step 3 cheap.

### Which work item

Whichever identifier "Recording the work item" resolved. That is the only source.

- **No identifier there** - set `<PLANE_OUTCOME>` to `not-inferred` and skip the rest of this section. Do not re-derive a candidate and do not scan the conversation for one; the reasons in that section apply here unchanged.
- **The PR already existed** (feature-branch flow, via Step 1's fall-through or Step 3's early exit) - this run never composed a body, so read the identifier off `<PR_FIRST_LINE>`, which Step 3's lookup already returned. Do not call `gh pr view` again for it.

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

## Reconciling the Plane state

This skill reconciles rather than transitions: it writes whatever state its own evidence implies, so a checkpoint missed for any reason self-corrects on the next ship instead of drifting further.

Record the result in `<STATE_OUTCOME>`; the Report step prints one line for it.

### Which state the evidence implies

- **`<PR_STATE>` is `ready`** → `states.in-review`. Flipping a draft to ready is the event that means review has started.
- **`<PUSHED_PATHS>` holds only paths under `docs/`** → `states.shaping`. The change so far is a spec.
- **`<PUSHED_PATHS>` holds anything outside `docs/`** → `states.implementing`.
- **Nothing was pushed and this is not a ready-flip** - set `<STATE_OUTCOME>` to `nothing-pushed` and skip the rest. A run that only re-checked a link has no evidence about the stage.

A repo that gitignores all of `docs/` can never produce a docs-only push, so that state only ever gets written by `/wf-shape` itself. That is a property of the repo's `.gitignore`, not a special case here.

### Writing it

The same procedure `/wf-shape` uses, pointed at a different phase.

1. Resolve the work item the way "Linking the PR to Plane" does - the identifier is decided in "Recording the work item" and there is one per ship. No identifier means `<STATE_OUTCOME>` is `not-inferred`; stop here. The `retrieve_by_identifier` call also returns `state`; save it too, alongside `id` and `project` - the guard below needs it.
2. Call `state` with `action: "list"` and `project_id` set to the work item's project.
3. **Check the guard first.** If the work item's current state belongs to a state in that list whose `group` is `completed` or `cancelled`, set `<STATE_OUTCOME>` to `already-closed`, leave it alone, and stop - do not read the target name at all. Compare against every state in those groups, not one named state: a project can close work items into more than one.
4. Only past the guard, read the target state name from `<WF_CONFIG>` as `<name>` and match it, exactly, against the same list.
5. **No match** - set `<STATE_OUTCOME>` to `no-such-state` and skip the write.
6. **A match** - call `workitem` with `action: "update"` passing only `state`, and set `<STATE_OUTCOME>` to `moved:<name>`.

A Plane failure never fails the ship. By the time this runs the PR exists; set `<STATE_OUTCOME>` to `failed`, keep the error text, and continue.

### Reporting it

One line, after the link line:

- `moved:<name>`: `- Moved <ID> to <name>.`
- `already-closed`: `- <ID> is already closed - state left as is.`
- `no-such-state`: `- No state change - <ID>'s project has no state named <name>.`
- `nothing-pushed`: `- No state change - nothing was pushed.`
- `not-inferred`: `- No state change - no work item known for this change.`
- `failed`: `- No state change - Plane returned: <error>.`
