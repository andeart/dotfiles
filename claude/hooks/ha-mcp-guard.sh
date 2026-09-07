#!/bin/bash
# PreToolUse: allow the Home Assistant MCP tools only under the desktop app.
#
# The bare CLI binary is not an .app bundle, so macOS never grants it local
# network access and its dial to the HA host fails with FailedToOpenSocket.
# Deny unless a bundle is positively identified: failing closed is the point,
# so every exit that is not that identification has to carry a deny with it -
# including a lib that never synced and a python3 that will not run.
set -uo pipefail

source "$HOME/.claude/hooks/lib/claude-exe.sh" 2>/dev/null

exe=""
if declare -f resolve_claude_exe >/dev/null 2>&1 &&
   declare -f is_bundled_claude >/dev/null 2>&1; then
  exe="$(resolve_claude_exe "$PPID")"
  is_bundled_claude "$exe" && exit 0
fi

CLAUDE_EXE="$exe" \
PYTHONPATH="$HOME/.claude/hooks/lib" /usr/bin/python3 -c '
import json, os
from ha_mcp_message import alert
print(json.dumps({"hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": alert(os.environ["CLAUDE_EXE"]),
}}))
' && exit 0

# python3 or the message module was unavailable, and the deny still has to be
# emitted. Written as literal JSON rather than built: the reason is plain ASCII
# with no quotes or backslashes, so there is nothing here to escape.
printf '%s\n' '{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "The Home Assistant MCP is desktop-app only in this repo. Reopen the repo in the Claude Code desktop app if you need the ha_* tools. This hook could not load its message module, so it cannot say more than that."}}'
exit 0
