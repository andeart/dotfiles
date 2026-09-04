# .wf.yml

Repo-level settings for the `wf-*` skill family, read by
`scripts/resolve-wf-config.sh`. The file is required, and so is every key in
it: nothing falls back, so a key the file leaves out halts the skill that reads
it. `/wf-config` writes the file, or fills in the keys it lacks, from
`wf.yml.template` beside this document. See "Where the file lives" below for
which directory is read - in a linked worktree it is not always this one, and
there `/wf-config` reports the inherited file rather than writing a second.

Sections group by concern rather than by skill, because `states` and
`workspace` are each read by more than one skill and a per-skill layout would
force an arbitrary owner.

## Keys

| Key | Type | Template value | Read by |
| --- | --- | --- | --- |
| `states.shaping` | string | `Shaping` | `/wf-shape`, `/wf-ship`, `/wf-status` |
| `states.implementing` | string | `Implementing` | `/wf-ship`, `/wf-status` |
| `states.in-review` | string | `In Review` | `/wf-ship`, `/wf-status` |
| `workspace.impl` | `base` \| `worktree` | `base` | `/wf-shape` |
| `review.reviewers` | list | `Alia`, `Bheem`, `Cristo`, `Darius` | `/wf-spec-review`, `/wf-impl-review` |
| `review.focus` | list | the four headings below | `/wf-spec-review`, `/wf-impl-review` |
| `ship.draft-by-default` | bool | `true` | `/wf-ship` |
| `verify.commands` | list | `[]` | `/wf-ship`, `/wf-spec-review`, `/wf-impl-review` |
| `wrap.watch-post-merge-ci` | bool | `false` | `/wf-wrap` |

The "Template value" column is what `/wf-config` writes into a repo that has
none, not a fallback: with the file in place, the value that applies is the one
the file carries.

The template's `review.focus`:

1. Security hardening
2. Performance
3. Cleanliness and maintainability of code
4. Succinct documentation that's not unnecessarily elaborate

## Where the file lives

Two directories, in order:

1. The repo root - `$(git rev-parse --show-toplevel)`, which inside a linked
   worktree is the worktree root.
2. Only when the root has no file of its own and the root is a linked worktree,
   the base clone that worktree was cut from.

The second entry exists because a `.wf.yml` that was never committed does not
travel into a worktree.

An inherited path is reported resolved - symlinks and `..` expanded - because
three skills show it beside the `verify.commands` they then run.

## Rules

- **Every key is required.** There is no required/optional tier: a tier would
  reintroduce the question this contract exists to remove, and each new key
  would arrive needing a judgment call about which side it lands on. A repo
  that wants nothing from a list key writes `[]`.
- **A list in the file is the whole list; it does not extend anything.** A
  roster of two names runs two review cycles, not six, and `/wf-config`'s merge
  applies the same rule - a shorter list replaces the template's outright
  rather than merging by index.
- **An explicitly empty list means none, deliberately.** `reviewers: []`
  resolves to `review.reviewers=<none>` and runs zero cycles. It is a decision
  the file states, and it is not the same answer as leaving the key out.
- **An unrecognised key is an error, not a no-op.** A key that is quietly
  ignored looks like a setting that applies and does not.
- **A key present with no value is an error.** A bare `key:`, `null` and `~`
  are all spellings of "no value" and all three are rejected. `<none>` is a
  list-only concept: a bool has no third state to express, and an empty state
  name cannot match any Plane state, so it would resolve to a write that is
  skipped every time. Run `/wf-config` to set the key.
- **A key set twice is an error.** yq collapses duplicates inside one document,
  so this only reaches a multi-document file - which would put two lines for
  one key in front of every skill-side check.
- **`verify.commands` entries are executed verbatim.** `/wf-ship` and both
  review skills run every entry from the repo root, as you, out of a file that
  travels with the repo. `/wf-config`'s sign-off is the only gate on them, and
  it only ever sees a file that skill just wrote - one that arrived with a
  clone, or was edited by hand, reaches the runners without passing it. So read
  the list before running a `wf-*` skill in a repo you did not configure. In a
  worktree the list can come from a file that is not in the working tree at all
  (see "Where the file lives"), so all three skills name the source: the two
  review skills at their go-ahead gate, `/wf-ship` in the Report afterwards
  since it never stops.
- **`verify.commands` entries should not overlap.** Check the listed commands
  for work one already does for another, and cut it as hard as the commands
  allow: the list runs in full on every ship and once per review cycle.
  Measured in this repo on 2026-08-30: `pre-commit run --all-files` took 86s, of
  which the `bats` hook was 83s, so a list naming both it and `tests/run.sh` ran
  the whole suite twice on every ship. `SKIP=bats` brings that run to 3s.
- **State names are matched against the project's Plane states by name.** A
  project without a matching state has that write skipped and reported, which
  is what lets the states be trialled in one project. DX-59 covers making that
  a loud failure once they exist everywhere.
- `states.*` names are matched rather than stored as identifiers, so one
  `.wf.yml` works across projects and workspaces where the same state carries
  different UUIDs.
- **"Closed" is a group concept, never a configured name - there is no
  `states.done` key.** `/wf-shape` and `/wf-ship` guard against rewriting a
  work item already in the `completed` or `cancelled` group. `/wf-wrap` guards
  only the `completed` group, and picks its own completion target from it
  rather than a name in `.wf.yml`.

## The state correspondence

`/wf-ship` decides a state from a push's file list and the pull request's
state; `/wf-shape` writes `states.shaping` unconditionally, since nothing has
been pushed yet when it runs. `/wf-status` reads a work item's current state
and flags a condition that holds when it does not match, observed from a
working tree and the pull request's current state. This table names only the
correspondence, not a procedure - each consumer states its own way of
observing a condition.

| State key | The condition it corresponds to |
| --- | --- |
| `states.shaping` | The branch's whole change touches only `docs/` |
| `states.implementing` | The branch's whole change touches anything outside `docs/` |
| `states.in-review` | The pull request is open and not a draft |

These two rows are read over the branch's whole divergence from the default
branch, not over one push's file list. The window is part of the condition: a
docs-only push onto a branch that already carries code does not make the change
a spec again. `/wf-ship` currently observes the narrower window and so can
disagree here - that is a defect in the writer, tracked separately, not licence
for a reader to copy it.

More than one row can hold at once - a ready pull request on a branch that
touches code matches both `states.implementing` and `states.in-review`. Which
one wins is the consumer's to state, not this table's; `/wf-ship` resolves it
by checking the pull request first, so the later stage wins.

Two of `/wf-status`'s checks have no writer and no `states.*` key, since
"closed" is a group concept rather than a configured name (see Rules above):

- The work item sits in the `completed` or `cancelled` group, and its branch
  has not merged.
- The identifier resolves to nothing in Plane.

## Reading it from a skill

One call, once per run, naming the keys the skill cannot run without:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh \
  --repo-root "$(git rev-parse --show-toplevel)" \
  --require states.shaping,workspace.impl
```

Every key emits at least one line, in a fixed order, list members 1-indexed:

```text
states.shaping=Shaping
workspace.impl=base
review.reviewers.1=Alia
verify.commands=<none>
wrap.watch-post-merge-ci=true
```

Two markers carry what a value cannot:

| Marker | Means | What a skill does |
| --- | --- | --- |
| `key=<unset>` | The file did not declare it | Nothing - `--require` has already halted the run if the skill named that key |
| `key=<none>` | Declared as an empty list | Proceed with zero members |

**`--require` is the halt.** Name every key the skill cannot run without,
comma-separated; the resolver exits `4` and prints the line the skill shows the
user verbatim. Naming a key the resolver does not know is a usage error rather
than a halt, since a halt on something that is not a key could never be cleared
by running `/wf-config`. The flag is opt-in because `/wf-wrap` must not gain a
way to fail - by the step that reads its key the worktree is gone and the branch
deleted - so it passes none and treats `<unset>` as an outcome instead.
`/wf-config` passes none either, for the opposite reason: a file short of keys
is the input it exists to fix.

**`--print-config-path` prints which file was resolved**, or nothing, and exits
before any `yq` work. It reads no YAML, so it can reach exit `0` and exit `2`
and never `3` or `4` - it cannot reject a file. Passing it with `--require` is
a usage error rather than a precedence rule, since a caller that got a path
back from a run it believed had validated the file would be wrong with nothing
to tell it. The four skills that disclose an inherited source use it; a skill
that only needs values has no reason to.

A skill that needs a value still walks the dump: a key is present when a line
starts with `key=` or `key.`, and a list arrives three ways - `key=<unset>`,
`key=<none>`, or `key.1=` and up. To walk a list's members, read `key.1`,
`key.2`, ... until a line is missing.

The markers are in-band, so a skill consumes the dump verbatim - read and
matched, never re-expanded. `yq -o=props` escapes a newline in a value to a
literal `\n` and keeps the value on one line, but zsh's `echo` would turn that
back into two, which is enough to forge a `wrap.watch-post-merge-ci=true` line
that a skill then reads as the repo's own setting. `AGENTS.md` already requires
these blocks to be portable across `/bin/bash` 3.2, bash 5 and zsh; this is the
same rule seen from the other side. The `--require` halt is out of reach of
that: it is computed inside the script from the parsed document, never from the
dump a caller re-expands.

Exit `0` resolved, `2` usage error (also what a missing `yq` produces), `3` a
config that is present but wrong, with the offending key named on stderr, `4` a
`--require` key the file never declared. An unset key is not exit 3: the file is
incomplete rather than malformed, and `/wf-wrap` needs to tell those apart while
treating both as non-fatal. `--print-config-path` reaches only `0` and `2`.

The parse is bounded. YAML aliases expand multiplicatively, so a document under
300 bytes can hold `yq` past any deadline at full CPU; the fork is killed at 10
seconds and reported as exit `3` naming the timeout rather than a key, which is
what keeps a skill's Step 0 block inside the Bash tool's own timeout.
`WF_YQ_TIMEOUT` overrides the deadline.
