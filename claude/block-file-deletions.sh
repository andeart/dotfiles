#!/usr/bin/env bash
# PreToolUse(Bash) hook: deny file-deletion commands.
#
# File deletions must be handed to the user to run themselves (see the
# deletion rules in ~/.agents/AGENTS.md). This hook reads the PreToolUse
# payload as JSON on stdin and, when a Bash command would delete files,
# returns a "deny" decision so the command never runs.
#
# Matches: rm / rmdir invoked as a command (this also catches `git rm`,
# `sudo rm`, `/bin/rm`, `xargs rm`, and `find -exec rm`, since each leaves
# `rm` as a whitespace-delimited token), and `find ... -delete`.
#
# It inspects the command string, so a deletion laundered through an
# interpreter (e.g. `python -c "import os; os.remove(...)"`) can still get
# through. This is a strong guardrail, not a perfect one.
#
# Fails open: on a malformed payload or a missing dependency it allows the
# command rather than blocking all of Bash.
set -uo pipefail

payload="$(cat)"

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

reason="Blocked by the block-file-deletions hook: this command would delete files. Per the deletion rules in AGENTS.md, deletions must be handed to the user - tell them exactly what to remove and let them run it themselves."

deny() {
  jq -cn --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# rm / rmdir invoked as a command.
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|`(])((/usr)?/bin/)?rm(dir)?([[:space:]]|[;&|)]|$)'; then
  deny
fi

# find ... -delete
if printf '%s' "$cmd" | grep -Eq '(^|[[:space:];&|`(])find[[:space:]].*-delete([[:space:]]|[;&|)]|$)'; then
  deny
fi

exit 0
