# .wf.yml

Repo-level settings for the `wf-*` skill family, read by
`scripts/resolve-wf-config.sh`. The file is optional: with none present every
key takes the default below.

Sections group by concern rather than by skill, because `states` and
`workspace` are each read by more than one skill and a per-skill layout would
force an arbitrary owner.

## Keys

| Key | Type | Default | Read by |
| --- | --- | --- | --- |
| `states.shaping` | string | `Shaping` | `/wf-shape`, `/wf-ship`, `/wf-status` |
| `states.implementing` | string | `Implementing` | `/wf-ship`, `/wf-status` |
| `states.in-review` | string | `In Review` | `/wf-ship`, `/wf-status` |
| `workspace.impl` | `base` \| `worktree` | `base` | `/wf-shape` |
| `review.reviewers` | list | `Alia`, `Bheem`, `Cristo`, `Darius` | `/wf-spec-review`, `/wf-impl-review` |
| `review.focus` | list | the four headings below | `/wf-spec-review`, `/wf-impl-review` |
| `ship.draft-by-default` | bool | `true` | `/wf-ship` |
| `ship.test-commands` | list | none | `/wf-ship` |
| `wrap.watch-post-merge-ci` | bool | `false` | `/wf-wrap` |

`/wf-status` arrives with DX-57's PR 4, reading `states.*` alongside the skills
already listed above.

The default `review.focus`:

1. Security hardening
2. Performance
3. Cleanliness and maintainability of code
4. Succinct documentation that's not unnecessarily elaborate

## Rules

- **A list in the file replaces its default; it does not extend it.** A roster
  of two names runs two review cycles, not six.
- **An explicitly empty list is treated as unset and takes the default.**
  `reviewers: []` and an absent `reviewers` key look identical to the
  resolver, so both give the four-name roster. To run fewer cycles, name the
  reviewers you want rather than emptying the list.
- **An unrecognised key is an error, not a no-op.** A key that is quietly
  ignored looks like a setting that applies and does not.
- **A key present with no value is an error.** A bare `key:`, `null` and `~`
  are all spellings of "no value" and all three are rejected. Remove the key
  to take its default.
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
| `states.shaping` | The change so far touches only `docs/` |
| `states.implementing` | The change touches anything outside `docs/` |
| `states.in-review` | The pull request is open and not a draft |

Two of `/wf-status`'s checks have no writer and no `states.*` key, since
"closed" is a group concept rather than a configured name (see Rules above):

- The work item sits in the `completed` or `cancelled` group, and its branch
  has not merged.
- The identifier resolves to nothing in Plane.

## Reading it from a skill

One call, once per run:

```bash
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh \
  --repo-root "$(git rev-parse --show-toplevel)"
```

Every setting comes back as `key=value` with defaults filled in, in a fixed
order, list members 1-indexed - except `ship.test-commands`, which has no
default and prints no lines when unset:

```bash
states.shaping=Shaping
workspace.impl=base
review.reviewers.1=Alia
ship.test-commands.1=bats tests/
wrap.watch-post-merge-ci=true
```

To walk a list key, read `key.1`, `key.2`, ... until a line is missing; a list
is absent when `key.1` is missing. That is how a skill detects that
`ship.test-commands` is unset.

Exit `0` resolved, `2` usage error (also what a missing `yq` produces), `3` a
config that is present but wrong, with the offending key named on stderr.
