---
name: wf-impl-review
description: Run a sequential multi-reviewer cycle over a branch's implementation, each reviewer writing notes and then revising the code. Use this skill whenever the user says "/wf-impl-review", "review this implementation", "run the impl review cycle", "run the reviewer cycle over this branch", or any variation of wanting implemented code reviewed before it merges. Do NOT trigger for reviewing a written spec - that is wf-spec-review. Do NOT trigger for a single-pass review of the current diff - that is the built-in code-review skill.
---

# Implementation Review Cycle

Run each reviewer in turn over a branch's committed changes. Every reviewer reads the code as it stands after the previous one's revisions, so the cycle compounds rather than repeating.

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
default=$(git rev-parse --verify --quiet main >/dev/null && echo main || { git rev-parse --verify --quiet master >/dev/null && echo master; })
echo "default=$default"
git check-ignore -q "$root/docs/reviews" && echo 'reviews_ignored=yes' || echo 'reviews_ignored=no'
echo 'wfconfig<<<'
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$(git rev-parse --show-toplevel)"
echo "resolver_exit=$?"
```

- `repo=no` - stop and say this is not a git repository.
- `origin=` empty - stop and tell the user no remote named `origin` is configured.
- `default=` - if empty, neither `main` nor `master` exists; stop and say so.
- `reviews_ignored=no` - **stop.** Say that `docs/reviews/` is not gitignored here, so each reviewer's commit would sweep its own notes into the branch. Ask the user to add it, and do not edit `.gitignore` yourself - that file is gated.

## Step 1: Resolve the roster and focus

Step 0's block already ran the resolver; its output is the lines after the `wfconfig<<<` marker and `resolver_exit=` is its exit status.

Read `review.reviewers.1`, `.2`, ... in order until a line is missing; that list is the roster and its length is the cycle count. Read `review.focus.1`, `.2`, ... the same way.

If `resolver_exit` is non-zero, stop and print its stderr - a broken `.wf.yml` is the user's to fix, and guessing a roster would run the wrong cycle.

## Step 2: Resolve the target and the identifier

**The target** is the branch's committed changes against the latest default branch; the skill takes no path argument.

**The identifier** comes from the branch name's leading identifier, read the way `wf-wrap` reads it: strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)` and uppercase the prefix (`dx-57-wf-authoring-skills` → `DX-57`). If the branch carries none and the user named none, ask for it - it names the review files and a wrong one writes into another work item's notes.

## Step 3: Pre-flight, then wait

Print exactly this, filled in, and stop for the user's go-ahead:

> Reviewing this branch's committed changes against `<default>` with `<N>` reviewers: `<names>`.
> Notes land in `docs/reviews/<id>-impl-review-<Name>.md` (gitignored).
> Each reviewer revises the branch before the next one starts. I'll push once at the end.
> Any concerns before we start the cycle?

The snippet this skill comes from ends its setup the same way. A cycle is `<N>` sub-agents times two prompts each; the user gets to stop it before that is spent.

## Step 4: Run the cycle

For each reviewer in roster order, one at a time. Never run two concurrently - each reads the previous one's revisions.

**Spawn a sub-agent** with the opening prompt below, verbatim. Substitute only `YourName`, the worktree path, the identifier, the focus list, and the resolved default branch. Give it nothing else - no extra context, no summary of earlier reviewers, no repo orientation. The genericity of the prompt is what makes each pass holistic. The numbered focus list carries one line per `review.focus` entry, however many the repo configures; the four shown below are this repo's defaults.

```text
I have changes committed in my worktree checked out at <ABSOLUTE WORKTREE PATH>. Review these changes against the latest `origin/<default>` holistically. Write your review feedback in normal markdown format to docs/reviews/<id>-impl-review-YourName.md within this branch. Note that docs/reviews/ is gitignored, which is fine.
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
```

**When that sub-agent finishes**, send it this follow-through with SendMessage, so it revises with its own review still in context:

```text
You're not obligated to, but you can now make changes on this branch. Let's follow through with your suggestions, as long as they don't reduce the quality of any of our other recent decisions on the branch.
- Run any appropriate tests/analyzers on this branch, and fix issues that arise.
- For any improvements or fixes you may make, once finalized, commit (but don't push) your changes on that branch.
```

Then move to the next reviewer.

The first reviewer may find no branch history to work from; that is expected and is not a reason to give it extra context.

## Step 5: Push and report

```bash
git push -u origin HEAD
gh pr view --json url --jq '.url' 2>/dev/null
```

A URL means a pull request already exists for this branch; the push updated it - report the URL. No output means there is none yet.

Report, one line per reviewer: its name, whether it wrote its notes file, and whether it committed a revision. Then the push result.
