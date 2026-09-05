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
[ -f "$root/.wf.yml" ] || echo "wfconfig_path=$(bash \
  ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh \
  --repo-root "$root" --print-config-path 2>/dev/null)"
echo 'wfconfig<<<'
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$root" \
  --require review.reviewers,review.focus,verify.commands
echo "resolver_exit=$?"
```

- `repo=no` - stop and say this is not a git repository.
- `origin=` empty - stop and tell the user no remote named `origin` is configured.
- `default=` - if empty, neither `main` nor `master` exists; stop and say so.
- `wfconfig_path=` - absent means the repo root carries its own `.wf.yml` and nothing below changes. A non-empty value is the file the settings actually came from, outside this working tree; Step 3 names it. An empty value means no config resolved anywhere, and nothing more - never fill it in as `$root/.wf.yml`.

## Step 1: Resolve the roster and focus

Step 0's block already ran the resolver; its output is the lines after the `wfconfig<<<` marker and `resolver_exit=` is its exit status.

`resolver_exit=2` (a usage error or a missing `yq`) or `resolver_exit=3` (a `.wf.yml` that is present but wrong) - stop and print its stderr. A broken config is the user's to fix, and guessing a roster would run the wrong cycle. Neither prints a dump, so there is nothing below to check.

The keys this skill reads:

- `review.reviewers.1`, `.2`, ... - the roster, in order; its length is the cycle count.
- `review.focus.1`, `.2`, ... - the topics each reviewer's opening prompt names.
- `verify.commands.1`, `.2`, ... - what Step 4 runs to establish the check state.

Step 0 passes that list to the resolver as `--require`, so the halt is the resolver's: `resolver_exit=4` means a key it names is not declared, and its stderr is the message to print verbatim before stopping. Nothing here re-derives it from the dump. `<none>` is never a halt - it is a list the file declared empty, deliberately. `tests/wf-config-halt-check.bats` pins this paragraph and the `--require` list beside it.

Read the roster and the focus list from the dump, `key.1`, `key.2`, ... in order until a line is missing.

`review.reviewers=<none>` - the repo configures no reviewers. Say so in one line and stop; zero cycles is what the file asked for, and there is nothing to spend a pre-flight on.

## Step 2: Resolve the target and the identifier

**The target** is the branch's committed changes against the latest default branch; the skill takes no path argument.

**The identifier** comes from the branch name's leading identifier, read the way `wf-wrap` reads it: strip a leading `worktree-` if present, then match the remainder against `^([a-zA-Z]+)-(\d+)` and uppercase the prefix (`dx-57-wf-authoring-skills` → `DX-57`). If the branch carries none and the user named none, ask for it - it names the review files and a wrong one writes into another work item's notes.

**The notes directory** is a fresh `<identifier>-review-notes` subdirectory created under this session's own scratchpad, the absolute path the session was handed for temporary files. Create the subdirectory rather than handing out the scratchpad root itself - a long-lived session's scratchpad can already hold another cycle's leftovers (a prior review's notes among them), and reusing it as-is puts every reviewer's notes in among whatever else is already sitting there. When the session has no scratchpad, run `mktemp -d` and use the fresh directory it creates directly. Either way, check the result before spawning anyone: it must be absolute, and it must not sit under the `$root` Step 0 resolved. A directory inside the working tree is what every reviewer after the first can read, and no step below re-checks the path. Leave the directory where it is when the cycle ends - an agent-run `rm` trips the deletion hook these repos carry, so the leftover is the expected outcome rather than a failure.

## Step 3: Pre-flight, then wait

Print exactly this, filled in, and stop for the user's go-ahead:

> Reviewing this branch's committed changes against `<default>` with `<N>` reviewers: `<names>`.
> Focus: `<focus list, comma-separated, or "none - holistic">`.
> Checks: `<verify.commands entries, comma-separated, or "none configured">`.
> Notes land outside the repo, in `<notes dir>/<id>-impl-review-<Name>.md`.
> Each reviewer revises the branch before the next one starts. I'll push once at the end.
> Any concerns before we start the cycle?

When Step 0's `wfconfig_path=` carried a value, add one more line directly below the `Checks:` line: ``> Settings came from `<wfconfig_path>`, not this working tree.`` The `verify.commands` entries the line above names are executed verbatim, so this gate is the place to say which file they arrived in. Leave the line out when `wfconfig_path=` was absent or empty.

The snippet this skill comes from ends its setup the same way. A cycle is `<N>` sub-agents times two prompts each; the user gets to stop it before that is spent.

## Step 4: Run the cycle

For each reviewer in roster order, one at a time. Never run two concurrently - each reads the previous one's revisions.

The check-state paragraphs below, through the no-bullet-items gate after the prompt template, are identical in `wf-spec-review/SKILL.md`'s Step 4 by design - the check-state chain and the follow-through gate apply to both skills the same way. Keep the two in sync: a wording change to one belongs in the other too.

**Establish the check state before the roster starts.** Run every `verify.commands` entry named in Step 0's resolver output, from the repo root and in order, timing each one as it runs, and record both the outcome and each elapsed time with `git rev-parse --short HEAD`. Reviewers otherwise each re-establish this for themselves: on the 2026-08-30 `wf-impl-review` run, before the prompt named the commands at all, all four ran the suite during their read-only phase, 25 invocations totalling roughly 40 minutes.

**`verify.commands=<none>`** - establish no check state; there is nothing to run and nothing to call green. Guessing a check command runs something arbitrary in a repo that never asked for it, the same reason `wf-ship`'s checks step declines to invent one.

Carry that state into every reviewer's opening prompt as `<CHECK_STATE>`, using these literal sentences:

- Every command passed - ``verify.commands is green at <SHA> - the exact command(s), with what each cost when I ran it: <verify.commands.1> (<elapsed>), <verify.commands.2> (<elapsed>), ... - run them after you've changed something, not before.``
- Any command failed - ``verify.commands is red at <SHA>, the commit you are starting from: <failing command> failed. The exact command(s), with what each cost when I ran it: <verify.commands.1> (<elapsed>), <verify.commands.2> (<elapsed>), ... - it was already red before you started, so the failure is not from anything you did.``
- No entries configured - ``this repo configures no verify.commands - there is nothing to run before or after your change.``

Naming the commands matters as much as the state does: a reviewer left to discover the command for itself finds `bats tests/` and takes the slow path instead of the fast one.

Naming what they cost matters for the same reason. Measured on the 2026-09-04 `wf-impl-review` run, one reviewer timed the suite for itself in a repeat loop during its read-only phase; the coordinator had already timed it and was discarding the number. Carry each elapsed time through, so a reviewer weighing a performance claim does not have to re-derive it.

**Re-establish it after any round that committed.** When a reviewer's follow-through produced a commit, re-run the commands at the new tip and carry the new state and sha forward. A round that committed nothing carries the previous state forward unchanged, with no re-run - the commit has not moved.

A failing state is still handed forward. It is a fact the next reviewer needs more than a passing one, and hiding it would have the next reviewer attribute the failure to its own change.

**Spawn a sub-agent** with the opening prompt below, verbatim. Substitute only `YourName`, the worktree path, the notes path, the identifier, the focus list, the resolved default branch, and `<CHECK_STATE>`. Give it nothing else about the review - no summary of earlier reviewers, no repo orientation, no account of what has already been found. The genericity of the prompt is what makes each pass holistic. Give the Agent tool call itself a `description` of exactly `Impl review: YourName` - `wf-cycle-timings` identifies and names every reviewer by matching that literal prefix against each sub-agent's own description, and a differently phrased one makes it find none.

The one exception is the check state below, and it is bounded deliberately: what crosses between reviewers is a fact about the tree, never a fact about the review. A reviewer learns that the checks pass at the commit it starts from; it does not learn who made them pass or what they thought.

The numbered focus list carries one line per `review.focus` entry, however many the repo configures. On `review.focus=<none>`, drop the `Focus your review of this on:` line and the numbered list with it, and leave the rest of the prompt as it stands.

```text
I have changes committed in my worktree checked out at <ABSOLUTE WORKTREE PATH>. Review these changes against the latest `origin/<default>` holistically. Write your review feedback in normal markdown format to <ABSOLUTE NOTES PATH>. That path is outside the repository, which is deliberate and fine.
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
- Do the reading yourself. Do not dispatch sub-agents to summarise the code, the history, or anyone else's notes - the round trip costs more than the reading it replaces.
- <CHECK_STATE>
```

**When that sub-agent finishes**, read its notes file and count the bullet items in it.

**No bullet items at all** - skip the follow-through, and name the reviewer in the report as having raised no bullet items. The opening prompt mandates a non-numbered bulleted list, so an absence of bullets means an absence of feedback. Count bullets and nothing else: a gate that judged whether a bullet was *actionable enough* could skip a revision that mattered, which would change what the cycle produces rather than only how long it takes.

**One or more bullet items** - send this follow-through with SendMessage, so it revises with its own review still in context. Drop the `Run <verify.commands>` bullet when no `verify.commands` entries were found above - the opening prompt already told it there is nothing to run:

```text
You're not obligated to, but you can now make changes on this branch. Let's follow through with your suggestions, as long as they don't reduce the quality of any of our other recent decisions on the branch.
- Run <verify.commands> (named in your opening prompt) and fix issues that arise.
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

Report, one line per reviewer: its name, whether it wrote its notes file, whether its follow-through ran or was skipped for raising no bullet items, and whether it committed a revision. Then the check state the cycle ended on, the directory the notes were written to, and the push result.

The notes are outside the working tree and are not cleaned up by `/wf-ship`. Name the directory so they can be read while the session's scratchpad still exists.
