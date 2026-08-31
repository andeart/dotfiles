---
name: wf-wrap
description: Wrap up work once a PR has merged, or once auto-merge is armed on it - mark the Plane work item Done, tear down the worktree if the work happened in one, switch back to the default branch, pull, and delete the merged feature branch. Use this skill whenever the user says "/wf-wrap", "wrap this up", "wrap up the merge", "post-merge cleanup", "switch back to main and clean up", "auto-merge is armed - clean up once it lands", or any variation of wanting to clean up after a PR merges or once auto-merge will land it. Do NOT trigger for shipping work for review (use /wf-ship) or for cleaning up older merged branches (use /wf-prune).
---

# Wrap Up After Merge

Run the post-merge cleanup sequence in one shot: mark the associated Plane work item as Done, get back to the default branch (tearing down the worktree if the work happened in one), pull, then delete the just-merged feature branch. Strong precondition checks; no confirmations once they pass.

Two facts shape the order below, and both are load-bearing:

- **Merges here are squashes.** The default branch gets a brand-new commit, so the feature branch tip is never an ancestor of it, and every ancestry test (`git merge-base --is-ancestor`, `git branch --merged`, `git branch -d`) reports fully-merged work as unmerged. Step 1 works around this once by comparing patch content; later steps inherit that result.
- **The work often happens in a linked worktree.** From inside one you cannot check out the default branch, and you cannot delete the branch you are standing on. So the worktree comes down before the pull, and the pull before the branch deletion.

## Output

Happy-path steps produce no progress output. Do not announce a step, do not confirm that a check passed, do not restate what a command returned, and do not explain what a section proved. On a successful run the Step 7 report is the only thing the user sees.

The one exception: a step that does something a reader would otherwise be surprised by gets a single short line naming what is happening and why - for example "Tearing down the worktree first because you cannot check out the default branch from inside one." One line, not a paragraph, and only where the surprise is real.

Everything else still reports in full. Every stop condition below, every failure, and every piece of work that was skipped rather than done gets the whole message it defines. Silence on the happy path is what makes the output that does appear worth reading.

A squash merge is the normal case here, not a finding. Step 1's `-` result is the normal case too. Neither gets a line.

## Step 0: Detect context and run the safety checks

One call answers everything this skill needs before it touches anything. Run it as a single command - the individual checks are cheap, but each separate call costs a round-trip:

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
git rev-parse --git-dir --git-common-dir --show-toplevel | { read -r a; read -r b; read -r c; echo "gitdir=$a"; echo "commondir=$b"; echo "toplevel=$c"; }
echo "upstream=$(git rev-parse --verify --quiet '@{upstream}')"
echo 'unpushed<<<'
git rev-parse --verify --quiet '@{upstream}' >/dev/null && git log '@{upstream}..HEAD' --oneline
echo 'status<<<'
git status --porcelain
```

The fetch runs first so every check below reads current remote state. `git rev-parse` takes all three path flags at once, which is the whole of the worktree detection. Lines between `unpushed<<<` and `status<<<` are unpushed commits; lines after `status<<<` are porcelain output.

All of these must pass before any destructive action runs. Any failure stops the skill immediately with a message naming the specific failure. Do not stash, do not commit-on-behalf, do not auto-recover.

- `repo=no` - stop and tell the user this isn't a git repository. Nothing else in the output is meaningful.
- `gh=no` - stop and tell the user `gh` is not on PATH.
- `origin=` empty - stop and tell the user no remote named `origin` is configured.
- `branch=` empty - HEAD is detached. Stop and tell the user to check out the feature branch first. Otherwise this is `<FEATURE>`.
- `default=` - this is `<DEFAULT>`. If it is empty, neither `main` nor `master` exists; stop and say so.
- `status<<<` followed by any lines - stop with:

  > Uncommitted changes on `<FEATURE>` - handle them before wrapping.

- `unpushed<<<` followed by any commits - stop and name them. They are not in the merge, so nothing below should discard them.
- `upstream=` empty - the upstream is gone. That is the normal state here, not a failure: merged PRs delete their head branch and any `--prune` fetch drops the tracking ref. Continue; Step 1 proves the same thing without the remote branch. An empty `unpushed<<<` section with a present `upstream` is equally fine.

**If `<FEATURE>` IS `<DEFAULT>`**, stop immediately and tell the user:

> You're already on `<DEFAULT>` - nothing to wrap up. If you wanted to clean up older merged branches, use `/wf-prune`.

Finally, resolve the worktree state from the three path lines. If `gitdir` and `commondir` differ, you are in a linked worktree: set `<IN_WORKTREE>` to yes, save `<WORKTREE_PATH>` from `toplevel`, and save `<PRIMARY>` as the directory containing `commondir`. Otherwise set `<IN_WORKTREE>` to no.

## Step 1: Establish that the PR merged, and prove nothing is lost

Look up the PR for `<FEATURE>`. Read the state, number, URL, merge commit, head tip, and the top of the body in one call - Step 2 needs that body and `gh` is network-bound, so a second lookup is the most expensive duplicate this skill can make:

```bash
gh pr view --json state,number,url,body,mergeCommit,headRefOid,autoMergeRequest --jq '.state, .number, .url, (.mergeCommit.oid // ""), .headRefOid, (if .autoMergeRequest == null then "disarmed" else "armed" end), "body<<<", (.body // "" | split("\n")[0:3] | .[])'
```

Six values come back in order - state, number, URL, merge commit SHA, the head branch's tip, whether auto-merge is armed - then a `body<<<` marker and the body's first three lines. Save the URL as `<PR_URL>` for the final report, the merge commit SHA as `<MERGE_SHA>` for Step 6, the head tip as `<HEAD_OID>` for Step 1c, the auto-merge flag as `<AUTO_MERGE>` for the branch below, and those body lines as `<PR_BODY_HEAD>` for Step 2.

If `gh` reports no PR for `<FEATURE>`, stop with:

> No PR found for `<FEATURE>`. Did you mean `/wf-ship` first?

If `state` is `MERGED`, continue to Step 1c.

If `state` is `OPEN` and `<AUTO_MERGE>` is `armed`, go to Step 1a instead of stopping.

Otherwise stop with:

> PR for `<FEATURE>` is `<state>`, not `MERGED`. Merge it before wrapping.

### Step 1a: Await an armed auto-merge

Print one line before polling - the Output section's stated exception, since a silent 15-minute wait is indistinguishable from a hang:

```text
Auto-merge is armed on PR <number>; waiting up to 15m for it to land. Ctrl-C stops the wrap - nothing has been changed yet.
```

Then poll, passing the number Step 1 already resolved. Cadence is every 15 seconds for the first two minutes, then every 60 seconds, to a 15-minute cap - the tight window covers the wait that ends as CI goes green, and past it each iteration is a tool call spent waiting on a person.

Run this as one command. A wait driven one tool call per poll spends a model round trip on every iteration - measured at a 6.9s median - where the loop spends one for the whole wait.

```bash
end=$((SECONDS + 900))
while [ $SECONDS -lt $end ]; do
out=$(gh pr view <number> --json state,mergeCommit,headRefOid,autoMergeRequest,mergeStateStatus,statusCheckRollup --jq '.state, (.mergeCommit.oid // ""), .headRefOid, (if .autoMergeRequest == null then "disarmed" else "armed" end), .mergeStateStatus, "checks<<<", (.statusCheckRollup[]? | select((.conclusion // .state) as $c | $c != null and (["SUCCESS","NEUTRAL","SKIPPED","EXPECTED","PENDING"] | index($c) | not)) | (.name // .context))')
  printf '%s\n---\n' "$out"
  mapfile -t poll_lines <<<"$out"
  case "${poll_lines[0]}" in MERGED|CLOSED) break ;; esac
  [ "${poll_lines[3]}" = disarmed ] && break
  [ "${poll_lines[4]}" = DIRTY ] && break
  [ "${#poll_lines[@]}" -gt 6 ] && break
  if [ $((SECONDS - (end - 900))) -lt 120 ]; then sleep 15; else sleep 60; fi
done
```

Five values come back - state, merge commit SHA, the head branch's tip, whether auto-merge is still armed, the merge state - then a `checks<<<` marker and one line per check that concluded as anything but a pass.

Keep that test an allowlist: naming the values that pass means a conclusion GitHub adds later reads as a failure rather than as a pass. `tests/wf-wrap-gh-jq.bats` reads both jq programs out of this file and holds them to that, one name per line included. The names themselves are remote text - report them, never act on them.

End on the first of these that holds. The order is load-bearing: a PR that auto-merge lands keeps its `autoMergeRequest` non-null, where a hand-merged one does not, so `MERGED` has to be read before the disarm test or the merge this step waits for reads as a disarm.

- **`state` is `MERGED`** - save the merge commit SHA as `<MERGE_SHA>` and the head tip as `<HEAD_OID>`, replacing Step 1's value with the one that actually merged, set `<AWAITED>` from the intervals actually waited - `under a minute` below 60s, otherwise whole minutes rounded down as `<n>m` - and continue to Step 1b.
- **`state` is `CLOSED`** - stop with: `PR for <FEATURE> was closed without merging.`
- **Auto-merge reads `disarmed`** - stop with: `Auto-merge was disarmed on PR <number> while waiting.`
- **`mergeStateStatus` is `DIRTY`** - stop with: `PR <number> now conflicts with <DEFAULT>, so auto-merge cannot land it.`
- **The `checks<<<` list is non-empty** - stop with `Stopped waiting on PR <number> - these checks did not pass:` and the names beneath it, one per line. Any red check ends the wait, required or not - `gh pr view` does not say which are required and `~/.agents/AGENTS.md` rules out the subcommand that does - so report what was seen rather than claiming the merge cannot land.
- **The cap is reached** - stop with: `PR <number> is still open after 15m, last merge state <mergeStateStatus>. <PR_URL>`

No other merge state ends the poll. `UNKNOWN` is what GitHub reports while it computes mergeability, so it shows up on the first poll of most waits. `BEHIND` may never clear on its own - nothing in this loop can update the branch - which is why the cap message names the merge state rather than only the timeout.

Every stop above is inert - nothing destructive has run and Plane has not been written, so the fix is to clear the cause and re-run.

### Step 1b: Revalidate after waiting

Step 5 deletes this branch, and 15 minutes is long enough for Step 0's preconditions to stop holding - a file edited in another pane, a commit made in another session - so prove them again:

```bash
git fetch --quiet origin
echo "branch=$(git symbolic-ref --short HEAD 2>/dev/null)"
git rev-parse --git-dir --git-common-dir --show-toplevel | { read -r a; read -r b; read -r c; echo "gitdir=$a"; echo "commondir=$b"; echo "toplevel=$c"; }
echo 'unpushed<<<'
git rev-parse --verify --quiet '@{upstream}' >/dev/null && git log '@{upstream}..HEAD' --oneline
echo 'status<<<'
git status --porcelain
```

`branch=` must still be `<FEATURE>`. Anything else means HEAD moved during the wait while every step below still acts on the saved name; stop with: `HEAD moved to <branch> during the wait - re-run /wf-wrap from <FEATURE>.` Re-resolve `<IN_WORKTREE>`, `<WORKTREE_PATH>` and `<PRIMARY>` from the three path lines with Step 0's rule, since Step 4 spends them. Then apply Step 0's `unpushed<<<` and `status<<<` rules unchanged - porcelain lines stop with its uncommitted-changes message, unpushed commits stop by naming them.

The fetch is required and is not a duplicate of Step 0's. The probe below compares against `origin/<DEFAULT>`, and on this path that ref was last read before the merge existed. Skip the fetch and the probe reports `+` for work that did land, which stops every awaited wrap.

### Step 1c: Prove nothing is lost

`gh` reporting `MERGED` says the PR merged; it does not say the local branch holds nothing the default branch lacks. Prove that separately, because Step 4 may discard the branch:

```bash
mb=$(git merge-base origin/<DEFAULT> <FEATURE>)
echo "head=$(git rev-parse <FEATURE>)"
git cherry origin/<DEFAULT> "$(git commit-tree "$(git rev-parse <FEATURE>^{tree})" -p "$mb" -m squash-probe)"
```

This squashes the branch's tree onto its own merge base and asks whether that patch is already upstream. A `head=` line comes back, then the probe's:

- `- <sha>` - an equivalent patch is on the default branch. The squash landed everything; discarding the branch loses nothing. Proceed silently: this is the expected result on every wrap, and saying so turns the guard into noise.
- `+ <sha>` - it did not. Show `git diff --stat $(git merge-base origin/<DEFAULT> <FEATURE>) <FEATURE>` in either case below, since that diff is the only thing that says what the branch is carrying and an unpushed commit produces a `+` under both. Then let `head=` name the case, and stop. **Equal to `<HEAD_OID>`** - the local branch is what merged, so the content should be upstream and is not. **Not equal** - the local branch is not what merged: `Local <FEATURE> is at <head>, PR <number> merged <HEAD_OID>. Fetch that tip with git fetch origin refs/pull/<number>/head before discarding anything.`

Compare against `<HEAD_OID>` rather than `@{upstream}`. A plain fetch does not prune, so once the merge deletes the head branch the tracking ref freezes at whatever Step 0 last saw - and a push made during an armed wait, which is the whole window this check exists for, never reaches it. That deletion is also why the recovery above names `refs/pull/<number>/head`: GitHub keeps that ref once the branch is gone, where `git pull` has nothing left to pull.

The probe commit is dangling and gets garbage-collected; no ref moves. Do not substitute `git diff <FEATURE> origin/<DEFAULT>` - it looks equivalent, but reports a difference as soon as any unrelated commit lands on the default branch, blocking legitimate wraps and training you to override the one guard that matters.

## Step 2: Resolve the Plane work item identifier

Two sources, both written deliberately for this change. In this order:

1. **The PR body** - `wf-ship` puts `Issue: [<ID>](<plane-url>)` on the first line whenever a work item is known. Step 1's lookup already returned it as `<PR_BODY_HEAD>`; do not call `gh pr view` again for it.

   Match `^Issue:\s*\[?([A-Z]+-\d+)\]?`. The optional brackets accept both the linked form and the bare `Issue: <ID>` that older PRs carry. No match means no candidate from this source.
2. **Branch name** - strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)`. Uppercase the prefix and join it to the number (e.g. `worktree-zzz-0-echo-slice` → strip → `zzz-0-echo-slice` → `ZZZ-0`; `zzz-1-foo-bar` → `ZZZ-1`). `EnterWorktree` prefixes the branches it creates, and without the strip those branches match nothing at all.
3. If neither yields a candidate, set `<PLANE_ID>` to `none` and `<PLANE_OUTCOME>` to `not-inferred`.

Do not scan the conversation for identifier-shaped strings. Identifiers appear there in discussion, in skill examples, and in tool output for reasons unrelated to the work being wrapped, and nothing distinguishes those from a real assignment. Both sources above are written for this change specifically; the transcript is not.

`ZZZ` is a placeholder, not a real project. Keep example identifiers in this file unresolvable.

The candidate is provisional at this point. Validation happens in Step 3. Once `<PLANE_ID>` is set, do not mutate it again - track what happened in `<PLANE_OUTCOME>` instead.

## Step 3: Update Plane (only if `<PLANE_ID>` was resolved)

This runs **before** anything destructive, so a Plane failure leaves both the worktree and the branch intact as a recovery point.

Skip this step entirely if `<PLANE_ID>` is `none` (Step 2 already set `<PLANE_OUTCOME>` to `not-inferred`). Otherwise:

1. Call the Plane MCP tool `workitem` with `action: "retrieve_by_identifier"` and `workitem_identifier` set to `<PLANE_ID>` whole - the tool takes `ZZZ-0`, not the prefix and number as separate arguments. If it returns 404 (or any not-found error), set `<PLANE_OUTCOME>` to `not-found` and skip the remaining sub-steps. The inferred `<PLANE_ID>` value is preserved for the report. This is not a fatal error.
2. From the response, save the work item's `id` field as the work item UUID, the `project` field as the project UUID, and the `state` field as the current state UUID.
3. Call `state` with `action: "list"` and `project_id` set to the project UUID. Collect every state whose `group` is `"completed"`. Pick the one named `"Done"` if it exists, otherwise the first. If the project has no `completed` state at all, set `<PLANE_OUTCOME>` to `no-completed-state` and skip the remaining sub-steps.
4. If the current state UUID is already one of those `completed` states, set `<PLANE_OUTCOME>` to `already-done` and skip the update. Compare against the whole group, not just the state picked in sub-step 3 - a project can complete work items into more than one state, and rewriting one of those to "Done" would erase that distinction.
5. Call `workitem` with `action: "update"`, `project_id` set to the project UUID, `workitem_id` set to the work item UUID, and `state` set to the completed state's UUID. The parameter is `workitem_id`, not `work_item_id`. Do not pass any other fields. On success, set `<PLANE_OUTCOME>` to `updated`.

Then make sure the PR is linked, whatever `<PLANE_OUTCOME>` those sub-steps produced. The one exception is `not-found`, which never got as far as reading the UUIDs and so has nothing to link against. `wf-ship` attaches `<PR_URL>` to the work item's Links sidebar when it ships, but it cannot always get there: Plane may have been down for that ship, or the PR may predate the step that does it. This is the last point where anything still knows both the work item and the PR, so it is the last chance to make the link exist.

1. Call `workitem_link` with `action: "list"`, `project_id`, and `workitem_id`.
2. If any result's `url` equals `<PR_URL>` ignoring a trailing slash, set `<PLANE_LINK>` to `present` and do nothing else.
3. Otherwise call `workitem_link` with `action: "create"`, `project_id`, `workitem_id`, and `url` set to `<PR_URL>`, and set `<PLANE_LINK>` to `backfilled`.

If the state sub-steps hit a non-404 error (network, auth, server), stop and report. Nothing has been torn down yet - fix Plane (e.g. set the state in the UI), then re-run.

The link calls are the exception to that rule: they run after the state is already correct, and the link is a convenience rather than the point of the wrap. On any error there, set `<PLANE_LINK>` to `failed`, keep the error text, and carry on into Step 4. Blocking a cleanup over a sidebar entry would leave the branch and worktree standing for no good reason.

## Step 4: Get back to the default branch and pull

### If `<IN_WORKTREE>` is no

```bash
git checkout <DEFAULT>
```

### If `<IN_WORKTREE>` is yes

Never `git checkout <DEFAULT>` from a linked worktree - git refuses, because the primary checkout already holds that branch. Tear the worktree down instead.

**Start with `ExitWorktree`, `action: "remove"`.** Three outcomes:

- **It removes the worktree and its branch.** Done, continue to the landing check.
- **It refuses, listing commits not on the original branch.** A squash merge guarantees this for every branch, so it is the expected outcome rather than a problem to report. Step 1 already proved the content is upstream, so re-invoke with `discard_changes: true`. **Never pass that flag without Step 1's `-` result in hand** - it is the one place in this skill where work can actually be lost.
- **It reports no active worktree session, or declines to remove this worktree.** It only manages worktrees it created this session; one made with `git worktree add`, one from an earlier session, or one entered by path is out of scope. Re-invoke with `action: "keep"` to restore the session's working directory before the directory disappears (harmless if that is a no-op too), then use the fallback.

**Fallback:**

```bash
cd <PRIMARY>
git worktree remove -f -f <WORKTREE_PATH>
```

Two `-f` flags, and both are required. `EnterWorktree` locks the worktrees it creates, and a single `--force` does not override a lock - it fails with `cannot remove a locked working tree`. The second `-f` is what overrides it. (`git worktree unlock <WORKTREE_PATH>` first also works, but errors on a worktree that isn't locked, which the non-`EnterWorktree` cases here are.)

The fallback removes the directory but not the branch; Step 5 handles that.

### Confirm where you landed

Neither path guarantees you land on `<DEFAULT>`. `ExitWorktree` restores the directory you started in, and the primary checkout sits on whatever branch it held when the worktree was created - often not `<DEFAULT>`, since `EnterWorktree` branches from `origin/<DEFAULT>` regardless of local HEAD.

Check where HEAD is and pull in one call. The pull lands on whatever branch is current, so skipping the check fast-forwards an unrelated branch onto the default branch:

```bash
[ "$(git symbolic-ref --short HEAD)" = "<DEFAULT>" ] || git checkout <DEFAULT>
git pull --ff-only origin <DEFAULT>
```

If `git pull --ff-only` fails (diverged history), stop with the git error. Do not force, rebase, or reset.

## Step 5: Delete the local feature branch

`ExitWorktree`'s `remove` deletes the branch along with the worktree, so it may already be gone. Treat "already gone" as success, but do not swallow a real failure:

```bash
if git show-ref --verify --quiet refs/heads/<FEATURE>; then git branch -D <FEATURE>; else echo "branch already deleted"; fi
```

Do not write this as `... && git branch -D <FEATURE> || true`. The `|| true` also masks `cannot delete branch '<FEATURE>' used by worktree at ...`, which means Step 4's teardown silently failed and the report would claim a cleanup that did not happen. If `git branch -D` errors, stop and show it.

Use `show-ref --verify refs/heads/...` rather than `git rev-parse --verify <FEATURE>`, which also matches a same-named tag. Use `-D` (uppercase) for the reason at the top of this skill: `git branch -d` does not recognize a squash merge, even though Step 1 proved the content landed.

## Step 6: Watch the post-merge run

Resolve the config once:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
```

**Exit 2 (`yq` missing) or exit 3 (a broken `.wf.yml`)** - unlike `wf-ship` and `wf-spec-review`, do not stop the skill. By this step the worktree is gone and the branch is deleted; failing now would report a completed cleanup as an error. Set Step 6's outcome to `config-error`, keep the stderr, and skip the rest of this step.

`wrap.watch-post-merge-ci` `false` or absent - skip this step entirely and say nothing. It is opt-in because nothing on the PR says whether a repo has CI worth watching, so the intent has to come from a key. Step 1a spends comparable wall-clock without one because the armed flag states that intent on the PR itself.

`true`, and `<MERGE_SHA>` is empty - set Step 6's outcome to `unidentified` and skip the rest of this step. A squash merge always produces a merge commit, so an empty value means the `gh` call changed shape, not that there is nothing to watch.

Otherwise, before polling, print one line naming what is being watched and the cap - the Output section's stated exception for a genuine surprise, since by this point the worktree and branch are already gone and a silent wait of up to 15 minutes would leave the user with no report of that irreversible work:

```text
Watching post-merge CI for <MERGE_SHA> (up to 15m) - the wrap itself is already done.
```

Where Step 1a ran, write `up to 15m more`. That wait has already spent time the user did not plan on, and this line is where the second cap becomes theirs to abandon.

Then poll for the run against the merge commit.

Run this as one command. A wait driven one tool call per poll spends a model round trip on every iteration - measured at a 6.9s median - where the loop spends one for the whole wait.

```bash
end=$((SECONDS + 900))
sleep 60
start=$SECONDS
while [ $SECONDS -lt $end ]; do
out=$(gh api "repos/:owner/:repo/actions/runs?head_sha=<MERGE_SHA>" --jq '.workflow_runs[] | "\(.id)\t\(.status)\t\(.conclusion // "-")\t\(.html_url)"')
  printf '%s\n---\n' "$out"
  if [ -z "$out" ] || ! cut -f2 <<<"$out" | grep -qv '^completed$'; then break; fi
  if [ $((SECONDS - start)) -lt 120 ]; then sleep 15; else sleep 60; fi
done
```

Four tab-separated fields come back per run: id, status, conclusion (`-` while pending), and the run URL - the red and timeout report lines below print that URL.

Key on `head_sha`, never on the branch. Post-merge the branch is the default branch, and a branch query returns every run on it including other people's. `~/.agents/AGENTS.md` also rules out the PR-checks subcommand, which 403s on a fine-grained PAT.

**Timings, pinned so nobody has to invent them.** Allow 60 seconds for a run to appear - GitHub takes a few seconds to create one - then poll every 15 seconds for the first two minutes and every 60 seconds after, to a 15-minute cap. Both wrong answers are bad: a short cap reports "still running" on every green build, a long one hangs the wrap. Where Step 1a ran, this cap follows that one, so a single wrap can block for half an hour, which is what the announce line above has to admit.

Six outcomes total, all reported in full - `config-error` and `unidentified` above, plus four more here:

- **Every run concluded `success`** - one line in the report.
- **Any run concluded otherwise** - fetch `gh api "repos/:owner/:repo/actions/runs/<id>/jobs"` and name the jobs that did not pass, with the run URL.
- **No run appeared within the grace window** - say so, naming `<MERGE_SHA>`.
- **A run is still going at the cap** - say so, with the run URL.

**A red run never fails the wrap.** By the time this runs the merge has landed and the branch is gone; there is nothing to roll back, and stopping here would strand the user with a cleanup half done and no report of it.

## Step 7: Report

Print a single block:

```text
Wrapped up <FEATURE>:
- Waited <AWAITED> for auto-merge to land.
- Marked <PLANE_ID> as Done.
- Removed the worktree at <WORKTREE_PATH>.
- Returned to <DEFAULT> and pulled.
- Deleted local branch <FEATURE>.
- Merged PR: <PR_URL>
```

The block shows the common case. `Waited` appears only when Step 1a ran; when `<IN_WORKTREE>` was no, omit the worktree line and write `- Switched to <DEFAULT> and pulled.` instead; and the Plane, link and CI lines take the forms below.

Switch on `<PLANE_OUTCOME>` for the Plane line:

- `updated`: `- Marked <PLANE_ID> as Done.`
- `already-done`: `- <PLANE_ID> was already in a completed state - left as is.`
- `not-inferred`: `- No Plane work item updated - none named in the PR body or branch name.`
- `not-found`: `- No Plane work item updated - <PLANE_ID> was inferred but not found in Plane.`
- `no-completed-state`: `- No Plane work item updated - project has no "completed" state.`

Then add a line for `<PLANE_LINK>`, but only when it has something to say:

- `backfilled`: `- Linked the PR on <PLANE_ID> - the ship had not.`
- `failed`: `- Could not link the PR on <PLANE_ID>: <error>. The wrap itself is done.`
- `present`: no line. The link being there is the expected case, and reporting it every wrap buries the two outcomes that matter.

Then add a line for Step 6's outcome, unless it was skipped:

- green: `- Post-merge CI passed.`
- red: `- Post-merge CI failed: <jobs>. <run URL>`
- absent: `- No post-merge CI run appeared for <MERGE_SHA> within 60s.`
- timeout: `- Post-merge CI still running after 15m. <run URL>`
- unidentified: `- Post-merge CI not checked - the merge commit could not be identified.`
- config-error: `- Post-merge CI not checked - config error: <stderr>.`
- skipped: print nothing.

The user always sees whether Plane was touched and why.
