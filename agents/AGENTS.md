## CRITICAL

- Never force push under any circumstances, even if asked.
- Never run `rm -rf` under any circumstances. If a destructive removal is needed, prompt the user to run it themselves.
- Never merge a PR without explicitly asking the user for confirmation first.

## Communication

- Say "I don't know" rather than guessing when uncertain.
- Ground factual claims with direct quotes from the source. If you can't find a supporting quote, retract the claim.
- For long documents (>20k tokens), extract relevant quotes before performing the task.
- If two things sound similar but might differ, say so - don't assert equivalence without verifying. When unsure, say "I'm not sure" or ask.
- Use simple dashes (-), never em-dashes (—).
- When asked to "add a rule" or "remember this rule", always add it to a CLAUDE.md file (repo-specific or global), never to memory.

## Git

- Never force push.
- Never add Co-Authored-By lines or any AI attribution to commit messages.
- Write commit messages in simple present imperative tense. The subject line should complete the sentence "This commit will…"
- Never use conventional commit style prefixes.
  - **Avoid:**
    - `feat: add dark mode support` - no prefixes
    - `fix(auth): resolve token expiry bug` - no prefixes or scope notation
    - `chore: update dependencies` - no prefixes
    - `Added dark mode support` - past tense, not imperative
    - `Adding dark mode support` - gerund, not imperative
  - **Prefer:**
    - `Add dark mode support`
    - `Fix token expiry bug in auth flow`
    - `Update dependencies`
    - `Remove deprecated API calls`
    - `Refactor settings page layout`

## GitHub Issues & PRs

- Write issue and PR descriptions in a human, personable voice. First-person observations over passive/abstract phrasing ("I traced this back to..." not "The root cause was identified as...").
- Lead with your perspective or lived experience before getting into rationale. Share a take, then support it.
- Keep technical detail rigorous and well-structured - the tone is friendly, not the standards.
- Avoid formal/corporate phrasing like "undermines the contract" or "addresses this gracefully" - prefer plain language like "so users end up hunting for files they shouldn't have to know about" or "should be enough to cover that."
- Nothing overly jovial or silly. The goal is to sound like a thoughtful contributor talking to maintainers, not a spec generator.

## Security

- Never publish details about a repo's security posture in that repo's own public metadata (PR or issue descriptions, commit messages, comments, release notes). The repo where a defense lives is exactly the place an attacker is already reading.
- Things that count as "security posture" and do NOT belong in public metadata: environment names paired with their branch or reviewer restrictions, actor/identity gates and their rationale, which protections are intentionally OFF, which mutable tags were SHA-pinned and why.
- Public metadata should describe WHAT changed and WHY IT EXISTS AT ALL, not HOW THE DEFENSE IS SHAPED. Config and workflow files are unavoidable public surface; commit messages and PR bodies are not - keep them minimal.
- If a description you're about to publish reads like a hardening writeup, stop and ask before shipping.

## Tool Usage

- Never truncate output from linters, test runners, or compilers. Errors and summaries appear at the end - using `head` hides them. If output is long, use `tail` to see the summary.
