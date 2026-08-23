# GitHub

Native noun: **issue**.

Identifiers are `#<number>` inside the repo, or `<owner>/<repo>#<number>` from anywhere else. Use
the qualified form in Notes when referencing an issue in another repo - GitHub links both.

Everything here is the `gh` CLI, verified against `gh` 2.97.0. There is no MCP server in play, so
every call is a Bash call and every one takes `--repo` explicitly rather than relying on the
current directory.

## Config: `.workitems.github.yml`

| Key | Description | Example |
| --- | ----------- | ------- |
| `mode` | `gh` (default) or `manual` | `manual` |
| `repo` | `OWNER/REPO` the issues land in. Passed as `--repo` on every call. | `anuragd/homelab` |
| `assignee` | GitHub login, or `@me` | `anuragd` |
| `labels` | The repo's labels, each `{ name, id?, info? }` - same annotated shape Plane uses | see below |
| `milestone` | Milestone title to file into | `v2` |
| `project` | Projects v2 title, passed to `--project` | `Home` |
| `type` | Issue type name, passed to `--type` | `Bug` |
| `estimate_labels` | Map of Fibonacci value → label name, for repos that track estimates as labels | `{5: "estimate/5"}` |
| `guidance` | Free-form prose (block scalar) with repo-wide context | see below |

`default_tracker` is also accepted; `RESOLUTION.md` covers it.

**If `guidance` is set, read it first** as background. It shapes wording and constraints but is
never itself a field.

`labels` takes the annotated shape - a list of maps with a required `name` and optional `info`
describing when the label applies:

```yaml
labels:
  - name: tech-debt
    info: "Use when the item's primary value is reducing future friction, not user-facing."
  - name: automation
    info: "Home Assistant automations and the scripts they call."
```

GitHub resolves labels, milestones, projects, and types by name rather than by id, so the `id`
field the Plane shape allows is unused here. Leave it out.

## Wire format

GitHub Flavored Markdown, exactly as `CONVENTIONS.md`'s chat preview renders it. This is the one
tracker where the preview and the wire format are the same text, which makes it the cheapest place
to sanity-check a body.

- `### Impact` / `### Notes` / `### Acceptance criteria` for section headers.
- `---` on its own line, with a blank line either side, for the rules between sections.
- `-` bullets for Impact and Notes.
- `- [ ]` for acceptance criteria. GitHub renders these as interactive checkboxes natively; no
  special markup is needed and none should be added.

Pass the body via `--body-file -` and write it on stdin. A multi-line body through `--body` has to
survive shell quoting, and a body containing backticks or `$` will not.

## Report fields

After `Issue:` and `Assignee:`, in this order: `State`, `Labels`, `Milestone`, `Type`, `Estimate`.

GitHub has no priority field, so the report carries no `Priority` line.

`Issue:` links as `[<owner>/<repo>#<number>](<url>)`, taking the URL from the create or view call's
`url` field. There is no slug to guess at here - `gh` returns the URL - so this line is always a
link.

## Creating

1. **Resolve the repo.** From `repo` in config. If it's absent, ask; do not infer it from the git
   remote, which may point at a fork or a mirror rather than where issues are tracked.
2. **Create** with the body on stdin:

   ```bash
   printf '%s' "$BODY" | gh issue create \
     --repo <OWNER/REPO> \
     --title <title> \
     --body-file - \
     --assignee <login> \
     --label <name> \
     --milestone <title> \
     --type <name>
   ```

   Repeat `--label` per label. Omit any flag whose value is unset rather than passing an empty
   string. `gh issue create` prints the new issue's URL on stdout; the number is its last path
   segment.
3. **Add relations** only if the user asked - see "Relations".
4. **Report** from the values just sent plus the returned URL.

`gh issue create` has no state flag. Issues open on create, so `State:` is `open`.

Adding to a Projects v2 board needs the `project` OAuth scope. If `--project` fails on scope, say
so and offer `gh auth refresh -s project` rather than silently dropping the flag - a work item
missing from the board is exactly the kind of thing nobody notices for a month.

## Refining

1. **Fetch:**

   ```bash
   gh issue view <number> --repo <OWNER/REPO> \
     --json number,title,body,labels,milestone,assignees,state,issueType,url
   ```

   Note whether an estimate label is present; its absence is what triggers the backfill.
2. **Apply:**

   ```bash
   printf '%s' "$BODY" | gh issue edit <number> \
     --repo <OWNER/REPO> --title <title> --body-file -
   ```

   `gh issue edit` replaces the body wholesale. Pass only `--title` and `--body-file` unless the
   user asked for other field changes; label changes are `--add-label` / `--remove-label`, which
   are additive rather than a replacement.

Diagnose against `CONVENTIONS.md`. GitHub-specific breakages worth looking for:

- Acceptance criteria as plain `-` bullets instead of `- [ ]`, so they render as prose rather than
  a checklist.
- Section headers at `#` or `##`, which collide with the issue title's own visual weight.
- `***` or `___` horizontal rules. They render, but `---` is what the rest of the corpus uses.

## Estimates

GitHub has no estimate field. Two honest options, and the config picks:

- **`estimate_labels` is set** - map the chosen Fibonacci value to a label name and pass it as
  another `--label`. If the chosen value has no entry, do not snap to a neighbouring one: say the
  repo's estimate labels don't cover it, and leave the estimate off.
- **`estimate_labels` is unset** - the estimate is not recorded. Show it in the chat preview
  anyway, per `CONVENTIONS.md`, and print `Estimate: -` in the report.

Projects v2 supports a real number field and would be the better home for this, but nothing here
has been verified against a live board, so it is deliberately not documented as a mechanism yet.
Fill this section in when the first repo needs it.

## Relations

Only when the user explicitly asks, or references a dependency in the conversation. All four take
issue numbers or URLs:

- `--blocked-by <number>` / `--blocking <number>` on `create`, or `--add-blocked-by` /
  `--add-blocking` on `edit`.
- `--parent <number>` on either, to file the issue as a sub-issue.
- `--add-sub-issue <number>` on `edit`, for the other direction.

External URLs have no dedicated home the way Plane's Links sidebar does. Put them in Notes as
ordinary markdown links.

## Default field values

When the user specifies otherwise and no config is present:

- **Assignee**: `@me`.
- **Repo**: required. Ask rather than inferring from the remote.
- **Labels, milestone, project, type**: unset. Never invented.
- **Estimate**: derived and shown, recorded only if `estimate_labels` says how.

## Manual mode

When `mode` is `manual`, run no `gh` commands. Print the title and fields as rendered markdown,
then the body fenced so it can be pasted into GitHub's issue form. Because the wire format is
already markdown, fence it as `markdown`:

````markdown
**Title:** <issue title>

**Fields**
- Assignee: <login>
- Repo: <owner/repo>
- Labels: <comma-separated, or "none">
- Milestone: <title, or "none">
- Estimate: <value, or "none">

**Description**

```markdown
<full issue body, exactly as it would be sent>
```
````

## Example

`CONVENTIONS.md`'s worked body, unchanged - on GitHub the preview form *is* the wire format:

```markdown
### Impact

- This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.

---

### Notes

- Presence detection should use Wi-Fi presence as the primary method for the first version.
- A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
- Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.

---

### Acceptance criteria

- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
