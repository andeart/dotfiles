---
name: suggest-commit
description: Suggest a git commit message based on the current diff and conversation context. Use this skill whenever the user asks to "suggest a commit message", "write a commit message", "what should I commit this as", "draft a commit", or any variation of wanting help writing a commit message. Also trigger when the user says "/suggest-commit". Do NOT trigger for actually committing (use /commit for that).
---

# Suggest Commit Message

Generate a commit message from the working tree and display it. One call to gather, one message out.

## Gathering the change

Everything the message needs comes from one command. Run it exactly as written - each piece split off costs its own round trip:

```bash
git status --porcelain && git diff HEAD --stat && git diff HEAD -U1 -- ':(exclude)*.lock' ':(exclude)*-lock.json'
```

What each part carries:

- **porcelain lines** - column 1 is the index, column 2 the working tree, `??` untracked. This is what separates staged from unstaged; the patch does not.
- **stat** - the shape of the change, lockfiles included, so an excluded patch never hides a touched file.
- **patch** - `-U1` because the message needs what changed, not the code around it. The pathspec carries no positive term on purpose: adding `.` would scope the diff to the current directory and quietly drop every change outside it.

Route on what comes back:

- **Anything staged** - describe only the staged files. The rest of the tree is out of scope for this message.
- **Nothing staged** - describe the whole working tree.
- **`??` entries** - untracked files carry no patch. The path usually says enough; read the file only when it doesn't.
- **Both columns non-space on one file** (`MM`, `AM`) - it has staged and unstaged edits both. Say so and ask which the message is for.
- **No output** - clean tree. Say there's nothing to write a message about and stop.
- **`fatal:` naming HEAD** - no commits yet, so `HEAD` doesn't resolve. Re-run as `git diff --cached`; every file is new.

The diff is the source of truth. Conversation context can sharpen the *why*, but the message must match what the diff shows, not what was discussed.

## Writing the message

Imperative present, as a command: the subject completes "This commit will ___". No conventional-commit prefixes - no `feat:`, no `fix(auth):`, no scope notation.

- Aim for a single line under 100 characters. Most commits change one thing and one line covers it.
- Reach for a body only when the change spans concerns a subject can't hold: subject, blank line, then a few imperative bullets. Not an essay.
- Say what the change does and why; the diff already carries the how. "Fix crash when user has no email" beats "Add null check on line 42 of user.py".

```text
Fix null pointer when rendering empty cart
```

```text
Refactor authentication flow

- Extract token refresh logic into dedicated module
- Remove unused session cookie handling
- Update tests to use new auth helpers
```

## Output

Emit the message in a code block and nothing else - no preamble, no recap of the diff, no offer to run the commit.
