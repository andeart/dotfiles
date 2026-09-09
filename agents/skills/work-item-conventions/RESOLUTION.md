# Resolving the Tracker

Which tracker a work item goes into is decided once, at the top of a run, by
`scripts/resolve-tracker.sh`. Both `file-work-item` and `refine-work-item` call it before doing
anything else, and `migrate-work-item-config` uses it to see what a repo already has.

Two more skills ask it narrower questions. `wf-ship` names `plane` outright and asks only where that
tracker's config is, for the workspace slug; `wf-config` reads the exit code and whether stdout came
back empty, to tell a repo with no tracker config from one that has some. `wf-wrap` goes straight to
the Plane MCP tools without reading any config at all, so filing and refining stay tracker-agnostic
while the ship and wrap workflows stay Plane-only.

**A normal run does not need this file.** The script's header holds the exit-code contract and the
branch order, and each caller carries its own call and the handling inline. Read this when a repo's
config layout is the question, or when changing how resolution works.

## Config files

Each tracker a repo files into gets its own `.workitems.<tracker>.yml`. A run picks one search root
before it looks for any of them: the repo root it was given when that root carries a tracker config,
and otherwise the base clone the root was cut from, when the root is a linked worktree. Under
whichever root wins, both the root's own file and its `tmp/` copy are read, and the root's own wins.
A config resolved from the base clone is reported resolved like any other, with the path saying
which directory it came from.

`tmp/` is for a config carrying something that shouldn't sit in a public tree - `guidance` prose
especially, and often the assignee and project identifiers. Whether a given repo's config qualifies
is the user's call, so `file-work-item` offers the location on a public repo rather than imposing it.
The offer only means anything where the repo actually ignores `tmp/`, which is a convention rather
than a guarantee, so it checks with `git check-ignore` first.

The tracker name in the filename is the whole detection signal. `.workitems.plane.yml` means this
repo files into Plane; a second `.workitems.github.yml` beside it means it files into both.

Every config supports one shared key:

| Key | Description |
| --- | ----------- |
| `default_tracker` | Which tracker wins when the repo has more than one config. Only consulted then. |

It is read from the config that wins for each tracker, so it can be set in whichever tracker's
config the user happened to open - though a copy under `tmp/` that a root-level file shadows is not
read. The configs must agree on it, and the value must name a tracker the repo actually has a config
for. A repo on a single tracker never needs the key.

Everything else in a config is that tracker's own business - see `references/<tracker>.md` for its
key set.

## Invoking the script

Resolution is a script rather than instructions in a SKILL.md because its four branches are the part
that can regress silently, and only a script can be pinned by a test.

Call it through `bash` rather than executing it directly: the sync that materialises these files
does not guarantee the executable bit survives, which is the same reason `gh-dependabot-config`
calls its script that way.

The script reads config files and nothing else - no writes, no network. Its reach is two directories
rather than one: a run that finds nothing under the root it was given reads that root's `.git`
pointer and the back-reference git writes beside the registration it names, and then reads configs
in the base clone. That is the property that would justify a permission-allowlist entry if one is
ever added off a real denial, and an entry scoped to the repo directory alone would now be short.
This says so rather than proposing one - `AGENTS.md` requires an entry to be built from a
demonstrated denial rather than estimated. `tests/resolve-tracker.bats` covers one repo fixture per
branch and pins the read-only guarantee across the worktree pair as well. That suite is the
contract; the script header is its summary.
