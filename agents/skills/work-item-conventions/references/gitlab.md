# GitLab

**This reference is a skeleton. It is not ready to file work items with.**

GitLab support was scoped alongside Plane and GitHub, but nothing here has been verified against a
live instance, and authoring plausible-looking mechanics that have never run would be worse than
having nothing: they read as authoritative right up until the call fails.

**If a run resolves to gitlab, stop and say so.** Do not improvise the mechanics, and do not fall back
to another tracker's. Offer to fill this file in against the repo at hand instead - that is the
point at which the details below become answerable.

Native noun: **issue**. Identifiers look like `#<iid>` within a project, or `<group>/<project>#<iid>` from outside. Note that the `iid` is per-project and is not the global `id` the API also returns.

## What this file needs

Fill these in, in this order, matching `plane.md` and `github.md` section for section. Each one is
answerable only against a real project.

### Config: `.workitems.gitlab.yml`

The key table. At minimum: how the project is addressed, who the default assignee is, and how
labels and any estimate mechanism are named. Keep the annotated `{ name, info }` entity shape the
other two references use, so the reasoning about which label applies stays identical across
trackers.

### Wire format

GitLab Flavored Markdown, which is close to GitHub's but not identical - task lists, tables, and reference syntax all have their own quirks worth confirming rather than assuming.

Whatever it turns out to be, the three sections, their order, their heading level, and the
interactive-checkbox requirement all come from `CONVENTIONS.md` unchanged. Only the markup that
expresses them belongs here.

### Report fields

Proposed order after `Issue:` and `Assignee:`: `State`, `Labels`, `Milestone`, `Weight`, `Estimate`. Confirm which of these the tracker
actually has before committing to it, and drop the ones it doesn't - a dash on a line for a field
that cannot exist is noise.

Also: whether the identifier can be linked from config alone, or whether a create call has to
return the URL.

### Creating, refining, relations

The call sequence for each, via the `glab` CLI, or the GitLab REST API. Refining needs a fetch that returns the current body, and a
write that replaces it.

### Open questions specific to GitLab

- Whether the estimate maps to GitLab's native issue weight, to a scoped label, or to time-tracking.
- How scoped labels (`priority::high`) should be used, given GitLab enforces one value per scope.
- Whether issues are addressed by project path or by numeric project id.
