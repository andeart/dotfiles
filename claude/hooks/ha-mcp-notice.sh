#!/bin/bash
# SessionStart: say up front that the HA MCP will not work under the bare CLI,
# so the failure is a sentence at startup rather than a cryptic socket error
# later. Silent under the desktop app, where the tools do work.
#
# Also silent when the binary cannot be identified. The guard takes the opposite
# default on that same unknown, deliberately: an unknown the guard lets through
# reaches the socket error this pair exists to replace, while an unknown the
# notice warns about tells the user their session is a bare Mach-O that nothing
# established, and tells the model the tools are blocked when they may not be.
set -uo pipefail

source "$HOME/.claude/hooks/lib/claude-exe.sh" 2>/dev/null
declare -f resolve_claude_exe >/dev/null 2>&1 || exit 0
declare -f is_bundled_claude >/dev/null 2>&1 || exit 0

exe="$(resolve_claude_exe "$PPID")"
[ -n "$exe" ] || exit 0
is_bundled_claude "$exe" && exit 0

CLAUDE_EXE="$exe" \
PYTHONPATH="$HOME/.claude/hooks/lib" /usr/bin/python3 -c '
import json, os
from ha_mcp_message import alert, agent_context
print(json.dumps({
    "systemMessage": alert(os.environ["CLAUDE_EXE"]),
    "hookSpecificOutput": {
        "hookEventName": "SessionStart",
        "additionalContext": agent_context(),
    }}))
'
exit 0
