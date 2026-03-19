## Communication

- If two things sound similar but might differ, say so - don't assert equivalence without verifying. When unsure, say "I'm not sure" or ask.
- Use simple dashes (-), never em-dashes (—).

## Git

- Never force push.
- Never add Co-Authored-By lines or any AI attribution to commit messages.

## Commit Conventions

- Write commit messages in simple present imperative tense. The subject line should complete the sentence "This commit will…"
- Never use conventional commit style prefixes.

**Avoid:**
- `feat: add dark mode support` - no prefixes
- `fix(auth): resolve token expiry bug` - no prefixes or scope notation
- `chore: update dependencies` - no prefixes
- `Added dark mode support` - past tense, not imperative
- `Adding dark mode support` - gerund, not imperative

**Prefer:**
- `Add dark mode support`
- `Fix token expiry bug in auth flow`
- `Update dependencies`
- `Remove deprecated API calls`
- `Refactor settings page layout`
