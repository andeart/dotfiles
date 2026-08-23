# Jira

**This reference is a skeleton. It is not ready to file work items with.**

Jira support was scoped alongside Plane and GitHub, but nothing here has been verified against a
live instance, and authoring plausible-looking mechanics that have never run would be worse than
having nothing: they read as authoritative right up until the call fails.

**If a run resolves to jira, stop and say so.** Do not improvise the mechanics, and do not fall
back to another tracker's. Offer to fill this file in against the repo at hand instead - that is
the point at which the questions below become answerable.

Native noun: **issue**. Identifiers look like `PROJ-123` - a project key, a hyphen, a number.

## What this file needs

`plane.md` and `github.md` are the shape to match, section for section, plus a `jira-creating.md`
holding the create-side half. Everything structural - the three sections, their order, their
heading level, the interactive-checkbox requirement - comes from `CONVENTIONS.md` unchanged. Only
the markup and the calls that express it belong here.

Each of these is answerable only against a real site:

- Which wire format the endpoint in use takes, and how a body that picks wrong fails. Atlassian
  Document Format JSON and wiki markup are both in play depending on API version.
- Whether Jira renders an interactive checkbox at all, and what markup gets one.
- Whether estimates go in story points - a custom field whose id varies per site - or in the
  time-tracking fields.
- How the project key, board, and sprint are addressed, and which of them the config needs to carry.
- Whether a transition is needed to set an initial state, since Jira states move through a workflow
  rather than being set directly.
- Which report fields exist, out of `State`, `Priority`, `Estimate`, `Epic`, `Sprint`, `Labels` -
  and whether the identifier can be linked from config alone or needs a create call to return the
  URL.
- Whether the calls go through the Atlassian REST API or a `jira` CLI.
- Which keys `.workitems.jira.yml` carries. Keep the annotated `{ name, info }` entity shape the
  other references use, so reasoning about which label applies stays identical across trackers.
