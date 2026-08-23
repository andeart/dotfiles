# GitLab

**This reference is a skeleton. It is not ready to file work items with.**

GitLab support was scoped alongside Plane and GitHub, but nothing here has been verified against a
live instance, and authoring plausible-looking mechanics that have never run would be worse than
having nothing: they read as authoritative right up until the call fails.

**If a run resolves to gitlab, stop and say so.** Do not improvise the mechanics, and do not fall
back to another tracker's. Offer to fill this file in against the repo at hand instead - that is
the point at which the questions below become answerable.

Native noun: **issue**.

## What this file needs

`plane.md` and `github.md` are the shape to match, section for section, plus a `gitlab-creating.md`
holding the create-side half. Everything structural - the three sections, their order, their
heading level, the interactive-checkbox requirement - comes from `CONVENTIONS.md` unchanged. Only
the markup and the calls that express it belong here.

Each of these is answerable only against a real project:

- How an issue is addressed: by project path or by numeric project id, and whether the `iid` in
  `#<iid>` is the per-project number or the global `id` the API also returns.
- Whether the wire format is GitHub-compatible markdown. Task lists, tables, and reference syntax
  are the three worth round-tripping before assuming.
- Whether the estimate maps to native issue weight, to a scoped label, or to time-tracking.
- How scoped labels (`priority::high`) should be used, given GitLab enforces one value per scope.
- Which report fields exist, out of `State`, `Labels`, `Milestone`, `Weight`, `Estimate` - and
  whether the identifier can be linked from config alone or needs a create call to return the URL.
- Whether the calls go through the `glab` CLI or the REST API.
- Which keys `.workitems.gitlab.yml` carries. Keep the annotated `{ name, info }` entity shape the
  other references use, so reasoning about which label applies stays identical across trackers.
