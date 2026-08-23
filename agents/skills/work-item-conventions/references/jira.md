# Jira

**This reference is a skeleton. It is not ready to file work items with.**

Jira support was scoped alongside Plane and GitHub, but nothing here has been verified against a
live instance, and authoring plausible-looking mechanics that have never run would be worse than
having nothing: they read as authoritative right up until the call fails.

**If a run resolves to jira, stop and say so.** Do not improvise the mechanics, and do not fall back
to another tracker's. Offer to fill this file in against the repo at hand instead - that is the
point at which the details below become answerable.

Native noun: **issue**. Identifiers look like `PROJ-123` - a project key, a hyphen, a number.

## What this file needs

Fill these in, in this order, matching `plane.md` and `github.md` section for section. Each one is
answerable only against a real project.

### Config: `.workitems.jira.yml`

The key table. At minimum: how the project is addressed, who the default assignee is, and how
labels and any estimate mechanism are named. Keep the annotated `{ name, info }` entity shape the
other two references use, so the reasoning about which label applies stays identical across
trackers.

### Wire format

Jira Cloud takes Atlassian Document Format (ADF) JSON on the v3 API and wiki markup on v2. Which one applies depends on the endpoint, and picking wrong produces a body that renders as escaped text.

Whatever it turns out to be, the three sections, their order, their heading level, and the
interactive-checkbox requirement all come from `CONVENTIONS.md` unchanged. Only the markup that
expresses them belongs here.

### Report fields

Proposed order after `Issue:` and `Assignee:`: `State`, `Priority`, `Estimate`, `Epic`, `Sprint`, `Labels`. Confirm which of these the tracker
actually has before committing to it, and drop the ones it doesn't - a dash on a line for a field
that cannot exist is noise.

Also: whether the identifier can be linked from config alone, or whether a create call has to
return the URL.

### Creating, refining, relations

The call sequence for each, via the Atlassian REST API, or the `jira` CLI if one is installed. Refining needs a fetch that returns the current body, and a
write that replaces it.

### Open questions specific to Jira

- Whether estimates go in story points (a custom field whose id varies per site) or in the time-tracking fields.
- How the project key, board, and sprint are addressed, and which of them the config needs to carry.
- Whether transitions are needed to set an initial state, since Jira states move through a workflow rather than being set directly.
