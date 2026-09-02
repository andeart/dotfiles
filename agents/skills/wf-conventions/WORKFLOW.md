# The wf-* workflow, in order

- **`/file-work-item`** - creates the item in Plane, to your conventions. (`/refine-work-item` to clean up an existing one.)
- **`/wf-shape DX-12`** - verifies the premises with live measurement, posts findings on the item, **stops for your answers**, then sets up the branch and brainstorms the spec.
- **`/wf-spec-review`** - four reviewers over the spec, in sequence, each revising it.
- *…you implement…*
- **`/wf-impl-review`** - same four reviewers over the branch's committed changes.
- **`/wf-ship`** - commits, pushes, opens a **draft** PR, runs `.wf.yml`'s checks, links Plane, reconciles the state, checks off criteria with evidence.
- **`/wf-ship ready`** - flips the draft, moves the item to In Review, hands back the cleanup command. Never inferred; you have to say `ready`.
- *…you merge, or arm auto-merge…*
- **`/wf-wrap`** - marks it Done, tears down the worktree if there was one, returns to the default branch, pulls, deletes the branch, watches post-merge CI.
- **`/wf-prune`** - separately, whenever: clears older merged branches.

**`/wf-status`** sits outside the sequence - run it any time to see where every thread stands, or `wf-status <repo paths>` from the shell for the git half alone.

Two things worth remembering: a dirty tree stops `/wf-ship` and `/wf-wrap` by design, and `.wf.yml` in the repo root controls the states, reviewers, check commands, and whether drafts and CI-watching are on. That file is required, and so is every key in it - a repo missing one halts the skill that reads it, and **`/wf-config`** writes the file or fills in what it lacks. `CONFIG.md` beside this file documents every key.
