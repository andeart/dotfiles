# Resolving the Tracker

Which tracker a work item goes into is decided once, at the top of a run, by
`scripts/resolve-tracker.sh`. Both `file-work-item` and `refine-work-item` call it before doing
anything else, and `migrate-work-item-config` uses it to see what a repo already has.

Those three skills are its whole reach. `wf-ship` and `wf-wrap` still speak to Plane directly and
read `.workitems.plane.yml` by name, so filing and refining are tracker-agnostic while the ship and
wrap workflows are not.

The decision is a script rather than instructions here because the branches below are the part
that regresses silently, and only a script can be pinned by a test. `tests/resolve-tracker.bats`
covers one repo fixture per branch.

**A normal run does not need this file.** Both skills carry the call and the exit-code handling
inline. Read it when the resolver asks for a human and the reason needs explaining, or when
changing how resolution works.

## Config files

Each tracker a repo files into gets its own `.workitems.<tracker>.yml`, at the repo root or under
`tmp/`. The root wins if both exist.

`tmp/` is for public repos where a root-level config would look out of place - it is
conventionally gitignored for scratch and local files, so the config stays out of the committed
tree without calling attention to itself.

The tracker name in the filename is the whole detection signal. `.workitems.plane.yml` means this
repo files into Plane; a second `.workitems.github.yml` beside it means it files into both.

Every config supports one shared key:

| Key | Description |
| --- | ----------- |
| `default_tracker` | Which tracker wins when the repo has more than one config. Only consulted then. |

Everything else in a config is that tracker's own business - see `references/<tracker>.md` for its
key set.

## Running the resolver

```bash
bash ~/.agents/skills/work-item-conventions/scripts/resolve-tracker.sh \
  --repo-root <repo> [--tracker <name>]
```

Pass `--tracker` only when the user named one. Leave it off otherwise; do not pass a guess.

Invoke it through `bash` rather than executing it directly: the sync that materialises these files
does not guarantee the executable bit survives, which is the same reason `gh-dependabot-config`
calls its script that way.

| Exit | Meaning |
| ---- | ------- |
| `0` | Resolved. stdout holds the tracker name. |
| `10` | Needs the user. stdout holds the candidates, one per line (possibly none); stderr says why. |
| `2` | Usage error - a bad flag, a missing directory, or a tracker name with no reference file. |

## The order it applies

1. **An explicitly named tracker in the request wins outright**, and no config is opened. "File a
   Jira ticket", "open a GitHub issue for this", "put it in GitLab" are instructions, not hints to
   weigh against whatever happens to be checked in. Pass it as `--tracker`.

   A tracker name that the script rejects is a real stop, not a cue to fall back to detection. It
   means there is no reference file for what the user asked for.
2. **Exactly one `.workitems.<tracker>.yml` in the repo implies that tracker.** No prompt, and
   `default_tracker` is never consulted - a repo on one tracker never has to carry the key.
3. **`default_tracker` decides when more than one config is present.** The key is read from every
   config, so it can be set wherever the user happened to open one. They must agree, and the value
   must name a tracker the repo actually has a config for.
4. **Otherwise, ask.** Exit 10 is the only path that reaches the user.

## Handling exit 10

Show the candidates on stdout and ask which one to use. Use the stderr line to say why you're
asking - "both a Plane and a GitHub config are here and neither sets `default_tracker`" is a
better prompt than a bare question.

Then offer to write the answer into `default_tracker` in the config for the tracker they chose, so
the next generically-phrased request doesn't ask again. Ask before writing, and write only on a
yes.

When there were no candidates at all, that is a repo with no work item config. Offer to create one
- `file-work-item` describes the shape - rather than asking which of nothing to use.

## Reading the reference file

Read `references/<resolved>.md` and only that one. The other reference files describe trackers this
run is not filing into; loading them spends context on mechanics that cannot apply and invites
mixing one tracker's field names into another's call.
