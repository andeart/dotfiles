# Resolving the Tracker

Which tracker a work item goes into is decided once, at the top of a run, by
`scripts/resolve-tracker.sh`. Both `file-work-item` and `refine-work-item` call it before doing
anything else, and `migrate-work-item-config` uses it to see what a repo already has.

Those three skills are its whole reach. `wf-ship` reads `.workitems.plane.yml` by name for the
workspace slug, and `wf-wrap` goes straight to the Plane MCP tools without reading any config, so
filing and refining are tracker-agnostic while the ship and wrap workflows stay Plane-only.

**A normal run does not need this file.** The script's header holds the exit-code contract and the
branch order, and both skills carry the call and the handling inline. Read this when a repo's
config layout is the question, or when changing how resolution works.

## Config files

Each tracker a repo files into gets its own `.workitems.<tracker>.yml`, at the repo root or under
`tmp/`. The root wins if both exist.

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

The script reads config files and nothing else - no writes, no network. That is the property that
would justify a permission-allowlist entry if one is ever added off a real denial, so it is worth
keeping true either way. `tests/resolve-tracker.bats` covers one repo fixture per branch and pins it.
That suite is the contract; the script header is its summary.
