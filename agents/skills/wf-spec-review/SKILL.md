---
name: wf-spec-review
description: Run a sequential multi-reviewer cycle over a design spec, each reviewer writing notes and then revising the spec. Use this skill whenever the user says "/wf-spec-review", "review this spec", "run the spec review cycle", "get the reviewers on this design", or any variation of wanting a written spec reviewed before implementation begins. Do NOT trigger for reviewing implemented code - that is wf-impl-review.
---

# Spec Review Cycle

Run each reviewer in turn over a design spec. Every reviewer reads the spec as it stands after the previous one's revisions, so the cycle compounds rather than repeating.

## Output

Happy-path steps produce no progress output. Announce nothing, confirm nothing, restate no command's return. The pre-flight summary and the final report are the only things the user sees.

Every stop condition, every failure, and every reviewer that ended without writing its file reports in full.

## Step 0: Resolve context

One call answers everything:

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'repo=no'; exit 0; }
echo 'repo=yes'
root=$(git rev-parse --show-toplevel)
echo "root=$root"
echo "branch=$(git symbolic-ref --short HEAD 2>/dev/null)"
origin=$(git remote get-url origin 2>/dev/null)
echo "origin=$origin"
[ -n "$origin" ] && git fetch --quiet origin
git check-ignore -q "$root/docs/reviews" && echo 'reviews_ignored=yes' || echo 'reviews_ignored=no'
echo 'wfconfig<<<'
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
echo "resolver_exit=$?"
echo 'specs<<<'
ls -t "$root"/docs/superpowers/specs/*.md 2>/dev/null
```

- `repo=no` - stop and say this is not a git repository.
- `origin=` empty - stop and tell the user no remote named `origin` is configured.
- `reviews_ignored=no` - **stop.** Say that `docs/reviews/` is not gitignored here, so each reviewer's commit would sweep its own notes into the branch. Ask the user to add it, and do not edit `.gitignore` yourself - that file is gated.

## Step 1: Resolve the roster and focus

Step 0's block already ran the resolver; its output is the lines after the `wfconfig<<<` marker and `resolver_exit=` is its exit status.

Read `review.reviewers.1`, `.2`, ... in order until a line is missing; that list is the roster and its length is the cycle count. Read `review.focus.1`, `.2`, ... the same way.

If `resolver_exit` is non-zero, stop and print its stderr - a broken `.wf.yml` is the user's to fix, and guessing a roster would run the wrong cycle.

## Step 2: Resolve the target and the identifier

**The spec path** is the skill's argument when given. Otherwise take the newest file from Step 0's `specs<<<` listing whose filename contains the identifier, matched case-insensitively, and say which one you picked in the pre-flight summary. If none match, **stop** and say no spec under `docs/superpowers/specs/` names this identifier - do not fall back to the newest spec overall, which belongs to another work item.

**The identifier** comes from the branch name's leading identifier, read the way `wf-wrap` reads it: strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)` and uppercase the prefix (`dx-57-wf-authoring-skills` → `DX-57`). If the branch carries none and the user named none, ask for it - it names the review files and a wrong one writes into another work item's notes.

**Whether the spec is tracked** decides whether a reviewer's revision gets committed. Run `git ls-files --error-unmatch <spec path>` from the repo root, discarding output; exit `0` sets `<SPEC_TRACKED>` to `yes`, anything else sets it to `no`. This repo gitignores all of `docs/`, so it is always `no` here; some repos in this family track `docs/superpowers/specs/` instead, where it is `yes`.

## Step 3: Pre-flight, then wait

Print exactly this, filled in, and stop for the user's go-ahead:

> Reviewing `<spec path>` with `<N>` reviewers: `<names>`.
> Notes land in `docs/reviews/<id>-spec-review-<Name>.md` (gitignored).
> Each reviewer revises the spec before the next one starts. I'll push once at the end.
> Any concerns before we start the cycle?

The snippet this skill comes from ends its setup the same way. A cycle is `<N>` sub-agents times two prompts each; the user gets to stop it before that is spent.

## Step 4: Run the cycle

For each reviewer in roster order, one at a time. Never run two concurrently - each reads the previous one's revisions.

The check-state paragraphs below, through the no-bullet-items gate after the prompt template, are identical in `wf-impl-review/SKILL.md`'s Step 4 by design - the check-state chain and the follow-through gate apply to both skills the same way. Keep the two in sync: a wording change to one belongs in the other too.

**Establish the check state before the roster starts.** Run every `verify.commands` entry named in Step 0's resolver output, from the repo root and in order, and record the outcome with `git rev-parse --short HEAD`. Reviewers otherwise each re-establish this for themselves: on the 2026-08-30 `wf-impl-review` run all four ran the suite during their read-only phase, 25 invocations totalling roughly 40 minutes.

**No `verify.commands` entries at all** - establish no check state; there is nothing to run and nothing to call green. Guessing a check command runs something arbitrary in a repo that never asked for it, the same reason `wf-ship`'s checks step declines to invent one.

Carry that state into every reviewer's opening prompt as `<CHECK_STATE>`, using these literal sentences:

- Every command passed - ``verify.commands is green at <SHA> - the exact command(s): <verify.commands.1>, <verify.commands.2>, ... - run them after you've changed something, not before.``
- Any command failed - ``verify.commands is red at <SHA>, the commit you are starting from: <failing command> failed. The exact command(s): <verify.commands.1>, <verify.commands.2>, ... - it was already red before you started, so the failure is not from anything you did.``
- No entries configured - ``this repo configures no verify.commands - there is nothing to run before or after your change.``

Naming the commands matters as much as the state does: a reviewer left to discover the command for itself finds `bats tests/` and takes the 84s path instead of the 26s one.

**Re-establish it after any round that committed.** When a reviewer's follow-through produced a commit, re-run the commands at the new tip and carry the new state and sha forward. A round that committed nothing carries the previous state forward unchanged, with no re-run. That covers two cases: no revision was made, or one was made to a spec this repo doesn't track (`docs/` is gitignored here, so `<SPEC_TRACKED>` is `no` and nothing was committed to re-check) - either way, the checks have nothing new to see.

A failing state is still handed forward. It is a fact the next reviewer needs more than a passing one, and hiding it would have the next reviewer attribute the failure to its own change.

**Spawn a sub-agent** with the opening prompt below, verbatim. Substitute only `YourName`, the spec path, the identifier, the focus list, and `<CHECK_STATE>`. Give it nothing else about the review - no summary of earlier reviewers, no repo orientation, no account of what has already been found. The genericity of the prompt is what makes each pass holistic.

The one exception is the check state below, and it is bounded deliberately: what crosses between reviewers is a fact about the tree, never a fact about the review. A reviewer learns that the checks pass at the commit it starts from; it does not learn who made them pass or what they thought.

The numbered focus list carries one line per `review.focus` entry, however many the repo configures; the four shown below are this repo's defaults.

```text
I have a spec written in my worktree at <ABSOLUTE SPEC PATH>. Review this spec holistically. Write your review feedback in normal markdown format to docs/reviews/<id>-spec-review-YourName.md within this branch. Note that docs/reviews/ is gitignored, which is fine. The spec file is the only deliverable. Every point you raise must be actionable as an edit to that spec. If a suggestion can only be carried out by writing implementation code, write it into the spec as a design note instead.
You are reviewing as YourName. Focus your review of this on:
1. <focus.1>
2. <focus.2>
3. <focus.3>
4. <focus.4>

- Be aware of other recent review-driven commits and how they shape these changes.
- For any claim you make to serve as the premise for a direction/decision, measure and confirm it first if it's possible to do so, before choosing the direction.
- Phrase all your review feedback in an imperative tone, as if you were a reviewer guiding the engineer author on what to change ("Let's ..."), and in a non-numbered bulleted list.
- If your feedback includes references to specific lines in files, make them local links to the local files with line numbers.
- Keep single lines on single lines, don't split them to forcefully wrap them (editors are capable of wrapping them in the UI).
- Do not make any other changes to this repo on your own, or run any write/deploy operations.
- <CHECK_STATE>
```

**When that sub-agent finishes**, read its notes file and count the bullet items in it.

**No bullet items at all** - skip the follow-through, and name the reviewer in the report as having raised no bullet items. The opening prompt mandates a non-numbered bulleted list, so an absence of bullets means an absence of feedback. Count bullets and nothing else: a gate that judged whether a bullet was *actionable enough* could skip a revision that mattered, which would change what the cycle produces rather than only how long it takes.

**One or more bullet items** - send this follow-through with SendMessage, so it revises with its own review still in context. Drop the `Run <verify.commands>` bullet when no `verify.commands` entries were found above - the opening prompt already told it there is nothing to run. Include the commit bullet only when Step 2's `<SPEC_TRACKED>` is `yes`; when it is `no` the spec lives somewhere this repo doesn't track (`docs/` is gitignored here), and there is nothing to commit:

```text
You're not obligated to, but you can now edit the spec on this branch. Let's follow through with your suggestions, as long as they don't reduce the quality of any of our other recent decisions on the branch.
- This feature is not built yet and this cycle is not where it gets built. Confine your edits to the spec file.
- The spec/design doc should not name another work item's state or hold an unowned TODO. An open question belongs on the work item that can act on it. Putting one here creates a claim nobody re-reads.
- Run <verify.commands> (named in your opening prompt) and confirm it's still green; a spec-only change should not move it.
- For any changes you make, once finalized, commit (but don't push) your changes on that branch.
```

Then move to the next reviewer.

The first reviewer may find no branch history to work from; that is expected and is not a reason to give it extra context.

## Step 5: Push and report

```bash
git push -u origin HEAD
gh pr view --json url --jq '.url' 2>/dev/null
```

A URL means a pull request already exists for this branch; the push updated it - report the URL. No output means there is none yet.

Report, one line per reviewer: its name, whether it wrote its notes file, whether its follow-through ran or was skipped for raising no bullet items, and whether it revised the spec. Then the check state the cycle ended on, and the push result.
