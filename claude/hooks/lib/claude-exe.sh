#!/bin/bash
# Resolve the executable backing the ancestor claude process.
#
# Installed machine-wide to ~/.claude/hooks/lib/ and sourced by hooks that live
# in other repos. Nothing here sources it; that is not evidence it is unused.
#
# ps -o comm= only yields "claude", so lsof is what actually distinguishes the
# bare CLI binary from the desktop app's bundled copy. Helpers are absolute:
# lsof lives in /usr/sbin, which a bare PATH would miss, and a failed lookup
# would otherwise read as "not a bundle" and deny the desktop app too.
#
# Echoes the path, or an empty string when it cannot be determined.
resolve_claude_exe() {
  local pid=$1 ppid comm
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    read -r ppid comm <<<"$(/bin/ps -o ppid=,comm= -p "$pid" 2>/dev/null)"
    [ -z "$comm" ] && return 0
    if [ "${comm##*/}" = "claude" ]; then
      /usr/sbin/lsof -p "$pid" -a -d txt -Fn 2>/dev/null | _lsof_first_name
      return 0
    fi
    [ "$ppid" = "1" ] && return 0
    pid=$ppid
  done
}

# First NAME value out of `lsof -Fn` output.
#
# lsof's default table cannot be parsed for this: NAME is the last column but
# not the last whitespace-delimited field, and the desktop app's copy lives
# under "Application Support", so splitting on whitespace yields a path that
# does not exist. -Fn emits one n-prefixed line per name, which has no such
# ambiguity.
#
# Split out from resolve_claude_exe so the space handling is gradeable from
# canned input: macOS kills copies of the platform binaries a test would
# otherwise stand in for the claude executable with, so there is no live
# process to point lsof at.
_lsof_first_name() {
  /usr/bin/awk '/^n/ { sub(/^n/, ""); print; exit }'
}

# True when the resolved path sits inside an .app bundle, which is the only
# form macOS will grant Local Network permission to.
is_bundled_claude() {
  case "$1" in
    *.app/Contents/MacOS/*) return 0 ;;
    *) return 1 ;;
  esac
}
