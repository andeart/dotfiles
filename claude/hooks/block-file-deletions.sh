#!/usr/bin/env bash
# PreToolUse(Bash) hook: deny file-deletion commands.
#
# File deletions must be handed to the user to run themselves (see the
# deletion rules in ~/.agents/AGENTS.md). This hook reads the PreToolUse
# payload as JSON on stdin and, when a Bash command would delete files,
# returns a "deny" decision so the command never runs.
#
# Matches: rm / rmdir invoked as a command, behind any prefix that leaves the
# token delimited (`git rm`, `sudo rm`, `xargs rm`, `find -exec rm`) and at any
# path, not just /bin and /usr/bin (`/opt/homebrew/bin/rm`, `$HOME/bin/rm`).
# A quote delimits the token too, so `bash -c "rm ..."` is caught. Also
# `find ... -delete`.
#
# It inspects the command string, so a deletion laundered through an interpreter
# that never spells the token (e.g. `python -c "import os; os.remove(...)"`) can
# still get through. This is a strong guardrail, not a perfect one.
#
# Over-matching is the safe direction here and is not worth narrowing: a denial
# costs one handover to the user, a miss costs a file.
#
# Fails open: on a malformed payload or a missing dependency it allows the
# command rather than blocking all of Bash.
set -uo pipefail

payload="$(cat)"

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[[ "$tool" == "Bash" ]] || exit 0

cmd="$(printf '%s' "$payload" | jq -r '.tool_input.command // empty' 2>/dev/null)" || exit 0
[[ -n "$cmd" ]] || exit 0

reason="Blocked by the block-file-deletions hook: this command would delete files. Per the deletion rules in AGENTS.md, deletions must be handed to the user - tell them exactly what to remove and print the equivalent \`rm\`/\`rmdir\` command with absolute paths in your reply, so they can run it themselves."

deny() {
  jq -cn --arg r "$reason" \
    '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# A token boundary: start of string, whitespace, a shell operator, or a quote.
# The quote is what reaches inside `bash -c "..."`, where the command being run
# is a string rather than a word of the outer command.
D='[[:space:];&|`("'\'']'
# An optional leading path. Any run of non-boundary characters ending in a
# slash, so a deletion binary is caught wherever it lives.
P='([^[:space:];&|`("'\'']*/)?'

# rm / rmdir invoked as a command.
if printf '%s' "$cmd" | grep -Eq "(^|$D)${P}rm(dir)?([[:space:]]|[;&|)\"']|\$)"; then
  deny
fi

# find ... -delete
if printf '%s' "$cmd" | grep -Eq "(^|$D)${P}find[[:space:]].*-delete([[:space:]]|[;&|)\"']|\$)"; then
  deny
fi

exit 0
