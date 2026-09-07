"""Shared wording for the Home Assistant MCP hooks.

The PreToolUse guard and the SessionStart notice describe the same situation to
the same reader, so the text lives here instead of being restated in each hook.
Editing one hook's copy is how the two drift apart.
"""

_LEAD = (
    "The Home Assistant MCP is desktop-app only in this repo. "
    "Reopen the repo in the Claude Code desktop app if you need the ha_* tools."
)


def alert(exe: str = "") -> str:
    """User-facing alert: the direct line first, then the mechanism.

    An empty exe means the walk never identified the binary. Only the guard
    passes that, and it denies on it, so the text has to say what was actually
    established rather than repeat a bare-Mach-O claim with nothing behind it.
    """
    if not exe:
        return (
            _LEAD + "\n\n"
            "Why: this session's executable could not be identified, and the guard "
            "denies rather than assume a bundle it never found. macOS grants local "
            "network access per executable and only to .app bundles, so a binary "
            "nothing has identified cannot be presumed to hold it. See DX-83."
        )
    return (
        _LEAD + "\n\n"
        "Why: macOS gates local network access per executable, and only .app bundles "
        "get a row under System Settings > Privacy & Security > Local Network. This "
        f"session is running {exe}, a bare Mach-O with no bundle around it, so there "
        "is no row to grant and none can be created. Granting the terminal app does "
        "not help either, because the permission does not inherit from the parent "
        "process. The kernel refuses connect() with EHOSTUNREACH, which Bun's fetch "
        "surfaces as FailedToOpenSocket, even though the route and ARP entry for the "
        "host are healthy and both the gateway and the public internet stay "
        "reachable. Apple-signed binaries are exempt from the restriction, which is "
        "why curl reaches the same host fine. The desktop app's copy carries the very "
        "same signing identity but sits inside claude.app, so it does get a grantable "
        "row. See DX-83."
    )


def agent_context() -> str:
    """Model-facing guidance. Deliberately not the user alert: this one says what
    to do instead, rather than explaining the mechanism."""
    return (
        "The home-assistant MCP server cannot connect in this session: it is running "
        "the bare Claude Code CLI binary, which macOS denies local network access. Do "
        "not attempt mcp__home-assistant__* tools, a PreToolUse hook denies them. For "
        "Home Assistant work here, drive the HA API with curl, which is Apple-signed "
        "and exempt from the restriction. Tracked in DX-83."
    )
