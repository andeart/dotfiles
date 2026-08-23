# GitHub: creating

The create-side half of `github.md`, split out so a refine run never loads it. Read it alongside
`github.md`, whose config keys, wire format, and report block both flows share.

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

When the user says nothing on the point and no config supplies one:

- **Assignee**: `@me`.
- **Repo**: required. Ask rather than inferring from the remote.
- **Labels, milestone, project, type**: unset. Never invented.
- **Estimate**: derived and shown, recorded only if `estimate_labels` says how.
