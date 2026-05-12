## CRITICAL

- Never force push under any circumstances, even if asked.
- Never run `rm -rf` under any circumstances. If a destructive removal is needed, prompt the user to run it themselves.
- Never merge a PR without explicitly asking the user for confirmation first.
- Never pass permission-bypass flags (such as `--dangerously-skip-permissions`) to spawned `claude` or other agent processes. The spawned process inherits the flag and runs without permission checks, so bypassing permissions on it grants a fresh agent unrestricted access without the user's consent. If a programmatic spawn is genuinely necessary, use a narrow `--allowedTools` allowlist and clearly notify the user of every tool being granted before spawning; otherwise, hand the command to the user to run themselves.

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
- Match the emotional register to the stakes. Describe the change matter-of-factly - what was happening, what changes now. "The preview was raw HTML; this renders it as markdown" lands better than "the markup drowns out the content."

## Permissions & capability grants

- When proposing changes to any capability-grant surface (IAM policies, K8s RBAC, GitHub PAT/OAuth scopes, sudoers, file ACLs, firewall rules, MCP tool allowlists, etc.) where the exact required set is uncertain, never include "best-estimate" entries. Every entry should have a demonstrated reason to exist.
- Start with the minimum already proven in use, run the workload, read the specific denial, and add only the exact action/permission/scope the error names, scoped as tightly as the named resource/target allows. Iterate until the workload passes - then stop. No "while you're at it" additions.
- If the application error wraps the underlying denial and the entry name isn't visible, surface the exact denied call from the relevant audit log (CloudTrail for AWS, audit log for K8s, GitHub audit log for PATs, etc.) before guessing.
- If multiple denials surface in one run, batch them into one update - but still one entry per denial, not "and a few related ones."

## Security

- Never publish details about a repo's security posture in that repo's own public metadata (PR or issue descriptions, commit messages, comments, release notes). The repo where a defense lives is exactly the place an attacker is already reading.
- Things that count as "security posture" and do NOT belong in public metadata: environment names paired with their branch or reviewer restrictions, actor/identity gates and their rationale, which protections are intentionally OFF, which mutable tags were SHA-pinned and why.
- Public metadata should describe WHAT changed and WHY IT EXISTS AT ALL, not HOW THE DEFENSE IS SHAPED. Config and workflow files are unavoidable public surface; commit messages and PR bodies are not - keep them minimal.
- If a description you're about to publish reads like a hardening writeup, stop and ask before shipping.

## Tool Usage

- Never truncate output from linters, test runners, or compilers. Errors and summaries appear at the end - using `head` hides them. If output is long, use `tail` to see the summary.
