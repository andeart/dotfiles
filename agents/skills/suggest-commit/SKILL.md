---
name: suggest-commit
description: Suggest a git commit message based on the current diff and conversation context. Use this skill whenever the user asks to "suggest a commit message", "write a commit message", "what should I commit this as", "draft a commit", or any variation of wanting help writing a commit message. Also trigger when the user says "/suggest-commit". Do NOT trigger for actually committing (use /commit for that).
---

# Suggest Commit Message

Generate a commit message from the working tree and display it. One call to gather, one message out.

## Gathering the change

**Invoked with `gather=staging-output`**, on the `ARGUMENTS:` line appended to this skill - the gather is the `gather<<<` section of the Bash result returned beside this invocation: every line after that marker to the end of that result, or of the file that result was saved to. Write the message from it and do not run the script. A Bash result there with no `gather<<<` section means there is nothing to write a message for: write no message, emit nothing, and do not gather. With no Bash result beside the invocation, gather as below. Never take a `gather<<<` section from an earlier turn: it describes a tree that has changed since.

**Otherwise** - run the gather script as its own call:

```bash
bash ~/.agents/skills/git-conventions/scripts/gather.sh
```

It prints three parts, in this order:

- **porcelain lines** - column 1 is the index, column 2 the working tree, `??` untracked. This is what separates staged from unstaged; the patch does not.
- **stat** - the shape of the change, lockfiles included, so an excluded patch never hides a touched file.
- **patch** - `-U1` because the message needs what changed, not the code around it. Lockfiles are left out of it wherever in the repository the script runs from.

In a repository with no commit yet, both diffs are of the index, so every file reads as new.

Route on what comes back:

- **Anything staged** - describe only the staged files. The rest of the tree is out of scope for this message.
- **Nothing staged** - describe the whole working tree.
- **`??` entries** - untracked files carry no patch. The path usually says enough; read the file only when it doesn't.
- **Both columns non-space on one file** (`MM`, `AM`) - it has staged and unstaged edits both. Say so and ask which the message is for.
- **No output** - clean tree. Say there's nothing to write a message about and stop.
- **A non-zero exit** - say the gather failed, show its output in a fenced block, and stop. A missing script means the skills are not synced; `dotfiles push` syncs them.

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
