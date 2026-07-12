#!/usr/bin/env bash
# PreToolUse(Bash) hook: deny git force-push commands.
#
# Force-pushing is never allowed (see the git rules in ~/.agents/AGENTS.md).
# This hook reads the PreToolUse payload as JSON on stdin and, when a Bash
# command would force-push, returns a "deny" decision so it never runs.
#
# Matches a `git push` (allowing global options like `git -C dir push` and
# `git --no-pager push`) that also carries a force in any spelling:
#   --force, --force-with-lease[=...], --force-if-includes, a short cluster
#   containing -f (e.g. -f, -fu), or a forced refspec (`push origin +main`).
# Detection is scoped to the push's own simple command (it stops at a shell
# separator), so `git fetch --tags --force && git push` and legitimate
# `--force` on other subcommands (fetch/clean/checkout) are left alone.
#
# It inspects the command string, so a force laundered through an interpreter
# or an alias the hook can't see may still get through, and a stray "push
# --force" inside a commit message could trip it. This is a strong guardrail,
# not a perfect one.
#
# Fails open: on a malformed payload or a missing dependency it allows the
# command rather than blocking all of Bash.
set -uo pipefail

payload="$(cat)"

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

reason="Blocked by the block-force-push hook: this command would force-push. Per the git rules in AGENTS.md, force-pushing is never allowed, even if asked. If a force-push is genuinely required, hand the exact command to the user to run themselves."

deny() {
  jq -cn --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# `git ... push ...` carrying a force flag or a forced (+) refspec, all within
# the push's own simple command (the [^;&|`] runs stop at a shell separator).
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|`(])git[[:space:]]([^;&|`]*[[:space:]])?push([[:space:]][^;&|`]*)?([[:space:]]--force|[[:space:]]-[[:alpha:]]*f[[:alpha:]]*([[:space:]]|=|$)|[[:space:]][+][^[:space:];&|`])'; then
  deny
fi

exit 0
