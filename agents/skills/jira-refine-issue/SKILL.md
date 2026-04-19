---
name: jira-refine-issue
description: >
  Refine an existing Jira issue so it matches Anurag's writing conventions. Use this skill
  whenever the user wants to improve, clean up, polish, rewrite, reshape, or tidy an issue that
  already exists in Jira. Also trigger when the user says "refine this ticket", "rewrite this in
  our style", "make this issue conform", "fix up ENG-123", "clean up this Jira issue", or points
  at a Jira issue key or URL and asks to improve its wording or structure. Do NOT trigger for
  creating new issues (use jira-create-issue) or for migrating from Linear (use
  jira-migrate-from-linear). Use alongside the Atlassian MCP tools (getJiraIssue, editJiraIssue).
---

# Jira Refine Issue

This skill rewrites an existing Jira issue's title and description so they match Anurag's house
conventions. The writing rules themselves live in a shared file that this skill and
`jira-create-issue` both Read, so refined issues come out indistinguishable from freshly created
ones.

**Before proposing any rewrite, Read `~/.claude/skills/jira-issue-conventions/CONVENTIONS.md`
and follow its rules for title, description format, description structure, and acceptance
criteria style.**

## Scope

Refining only touches **title** and **description**. It does not change:

- Assignee, priority, estimate, state, space, labels, components.
- Issue links, comments, worklogs, or history.

`.jira.yml` defaults are a *creation* concept and must not override an existing issue's fields.
If the user explicitly asks to also adjust a field (e.g. "and bump priority to High"), handle
that as a separate `editJiraIssue` call after the content rewrite is confirmed.

## MCP call flow

1. **Look up the cloudId** via `getAccessibleAtlassianResources` if it isn't already cached
   for this session. Reuse the cached value when possible.
2. **Fetch the current issue** via `getJiraIssue` using the issue key the user provided. Retrieve
   the description in both markdown and ADF form if available; markdown is what we'll rewrite
   against.
3. **Diagnose violations.** Compare the existing title and description against
   `CONVENTIONS.md`. Typical issues to look for:
   - Title does not start with "Fix " for a bug, or uses title case instead of sentence case, or
     describes symptoms rather than the deliverable.
   - Impact section missing, or written as "This fixes..." / "This adds..." instead of an
     outcome-oriented "This will...".
   - Notes and AC content intermingled, or AC items phrased as imperatives ("Add X") rather than
     declarative present tense ("X is added").
   - Acceptance criteria rendered as plain bullets (`-`) or numbered lists instead of checkboxes
     (`- [ ]`).
   - Testing step absent or not positioned last.
   - Section headers at the wrong level, or separators missing between sections.
4. **Propose the rewritten version to the user before writing.** Show the proposed new title
   and the full proposed markdown description in the chat, and wait for explicit confirmation.
   Refining is destructive to existing prose, so never edit silently. If the user wants tweaks,
   iterate in chat first.
5. **Apply the edit** via `editJiraIssue` with `contentFormat: "markdown"`. Pass only `summary`
   and `description` unless the user requested other field changes.

## Already well-formed

If the existing issue already satisfies the conventions, say so and make no edits. Summarize
why no rewrite is needed (e.g. "Impact, Notes, and AC are all in the right shape; title is
sentence case and starts with 'Fix '; nothing to change.") rather than forcing a rewrite just
because the skill was invoked.

## Manual mode

If the issue's repo has `.jira.yml` with `mode: manual`, or if the user asks for manual output,
do not call `editJiraIssue`. Instead, present the rewritten title and description in the same
markdown format described in the `jira-create-issue` skill's "Manual mode output format"
section, so the user can paste the refined version into Jira themselves.
