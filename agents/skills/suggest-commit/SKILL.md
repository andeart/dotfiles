---
name: suggest-commit
description: Suggest a git commit message based on the current diff and conversation context. Use this skill whenever the user asks to "suggest a commit message", "write a commit message", "what should I commit this as", "draft a commit", or any variation of wanting help writing a commit message. Also trigger when the user says "/suggest-commit". Do NOT trigger for actually committing (use /commit for that).
---

# Suggest Commit Message

Generate a commit message from the current state of the working tree, copy it to the clipboard, and display it.

## How it works

1. Read the git diff to understand what actually changed
2. Optionally glance at the conversation for motivation/context behind the changes
3. Draft a commit message
4. Copy it to the clipboard via `pbcopy`
5. Display it to the user

## Gathering the diff

Run `git diff --staged` first. If that's empty (nothing staged), fall back to `git diff`. If both are empty, tell the user there's nothing to base a commit message on.

The diff is the primary source of truth for the commit message. The conversation history is secondary - it can add flavor or clarify intent, but the message must accurately reflect what the diff shows, not what was discussed.

## Writing the commit message

**Voice and tense:** Use the imperative present tense, as if giving a command. "Add validation" not "Added validation" or "Adds validation". This is the standard Git convention - the message completes the sentence "If applied, this commit will ___."

**Length:** Aim for a single line under 100 characters. Most commits change one thing and one line is enough.

**When to use a body:** If the diff touches multiple concerns or the change needs explanation that doesn't fit in 100 characters, use a subject line + blank line + body. The body should be a short bulleted list of what changed, also in imperative tense. Keep the body concise - a few bullets, not an essay.

**What to focus on:** Describe *what* the change does and *why*, not *how*. The diff already shows the how. For example, "Fix crash when user has no email" is better than "Add null check on line 42 of user.py".

**Single-line example:**
```
Fix null pointer when rendering empty cart
```

**Multi-line example:**
```
Refactor authentication flow

- Extract token refresh logic into dedicated module
- Remove unused session cookie handling
- Update tests to use new auth helpers
```

## Clipboard

After drafting the message, copy it to the clipboard using `pbcopy` so the user can paste it directly into a commit message editor. Pipe the exact commit message text (no markdown formatting, no backticks, no extra commentary) into `pbcopy`.

Use a heredoc to preserve newlines for multi-line messages:

```bash
pbcopy <<'EOF'
the commit message here
EOF
```

## Output

After copying, display the commit message to the user in a code block so they can see what was copied. Keep your surrounding commentary minimal - just show the message and confirm it's in the clipboard.
