# GitHub: refining

The refine-side half of `github.md`, split out so a filing run never loads it. Read it alongside
`github.md`, whose config keys, wire format, estimates, and report block both flows share.

## Refining

1. **Fetch:**

   ```bash
   gh issue view "$NUMBER" --repo "$REPO" \
     --json number,title,body,labels,milestone,assignees,state,issueType,url
   ```

   Note whether an estimate label is present; its absence is what triggers the backfill.
2. **Apply:**

   ```bash
   printf '%s' "$BODY" | gh issue edit "$NUMBER" \
     --repo "$REPO" --title "$TITLE" --body-file -
   ```

   `gh issue edit` replaces the body wholesale. Pass only `--title` and `--body-file` unless the
   user asked for other field changes; label changes are `--add-label` / `--remove-label`, which
   are additive rather than a replacement.

Diagnose against `CONVENTIONS.md`. GitHub-specific breakages worth looking for:

- Acceptance criteria as plain `-` bullets instead of `- [ ]`, so they render as prose rather than
  a checklist.
- Section headers at `#` or `##`, which collide with the issue title's own visual weight.
- `***` or `___` horizontal rules. They render, but `---` is what the rest of the corpus uses.
