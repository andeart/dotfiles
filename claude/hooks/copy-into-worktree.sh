#!/usr/bin/env bash
# PostToolUse(EnterWorktree) hook: seed a new worktree with the untracked files
# it needs from the base clone.
#
# A worktree is cut from a commit, so nothing gitignored travels into it - a
# flavor config, a local .env, a credentials file. Which paths are worth
# carrying is repo knowledge, so they are named per repo in `.wf.yml` and read
# here through the same resolver the wf-* skills use.
#
# The keys this hook reads:
#
# - `workspace.copy-into-worktree` - the paths to carry from the base clone.
#
# No `--require`, unlike the skills that read this config: there is no user
# here to send to `/wf-config`, and a repo that never declared the key wants
# nothing copied rather than a failed tool call.
#
# Copies only. Nothing is ever removed or overwritten: an entry already present
# in the worktree is left alone whole, contents included. A directory that git
# materialised for a tracked file under it is therefore skipped with its
# gitignored siblings left behind in the base clone - name those files rather
# than the directory holding them. Re-entering a worktree changes nothing on
# disk, and reports each entry it found already there.
#
# Trust: the entries come from `.wf.yml`, the same file that already names the
# commands the wf-* skills run verbatim. The path checks below are not a
# sandbox around that grant, they keep a mistyped entry from writing outside
# the two trees.
#
# Fails open: a missing resolver, a missing yq, an unreadable payload or a
# failed copy leaves the worktree as it found it rather than failing the tool
# call.
set -uo pipefail

RESOLVER="$HOME/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

payload="$(cat)"

command -v jq >/dev/null 2>&1 || exit 0

tool="$(printf '%s' "$payload" | jq -r '.tool_name // empty' 2>/dev/null)" || exit 0
[ "$tool" = "EnterWorktree" ] || exit 0

# A response that reports failure gets nothing, not even the fallback below:
# the session is still standing in whatever tree it was in, and .cwd would name
# a worktree the user did not just enter - seeding that one restores files they
# had deliberately removed from it.
printf '%s' "$payload" | jq -e '(.tool_response // {})
  | ((.error // null) != null) or (.success == false) or (.is_error == true)' \
  >/dev/null 2>&1 && exit 0

# worktreePath is what the tool returns; .cwd is the fallback because the
# session's directory is the worktree by the time this runs, so a response
# shape that changes should not silently stop the hook.
worktree="$(printf '%s' "$payload" \
  | jq -r '.tool_response.worktreePath // .tool_response.data.worktreePath // .cwd // empty' 2>/dev/null)" || exit 0
[ -n "$worktree" ] && [ -d "$worktree" ] || exit 0

[ -f "$RESOLVER" ] || exit 0

# base_clone carries the trust check that separates a linked worktree from any
# directory whose .git file names one: git registers the relationship both ways
# and the resolver verifies the back-reference. Called rather than
# reimplemented, so there is one copy of that check - and in a child shell
# rather than sourced, because the resolver sets `-e` at the top and this hook
# must fail open.
base="$(bash -c '_WF_LIB_ONLY=1 . "$1" && base_clone "$2"' _ "$RESOLVER" "$worktree" 2>/dev/null)" || exit 0
[ -n "$base" ] && [ -d "$base" ] || exit 0

# Reports <unset> in a repo that never declared the key; the loop then
# matches nothing. See the header for why no --require.
dump="$(bash "$RESOLVER" --repo-root "$worktree" 2>/dev/null)" || exit 0

copied=""
present=""
missing=""
skipped=""
while IFS= read -r line; do
  case "$line" in
    # The bare spelling is <unset> or <none>; either way no member follows it.
    "workspace.copy-into-worktree="*) break ;;
    "workspace.copy-into-worktree."*) ;;
    *) continue ;;
  esac
  entry="${line#*=}"
  # A trailing slash would leave ${dest%/*} naming the destination itself
  # rather than its parent.
  while :; do case "$entry" in */) entry="${entry%/}" ;; *) break ;; esac; done
  [ -n "$entry" ] || continue

  # An absolute path or a `.`/`..` segment would put the destination outside
  # the worktree; a control character would forge a line in the report below.
  case "$entry" in
    /*) skipped="$skipped $entry"; continue ;;
    *[[:cntrl:]]*) skipped="$skipped <unprintable>"; continue ;;
  esac
  case "/$entry/" in
    */../*|*/./*) skipped="$skipped $entry"; continue ;;
  esac

  src="$base/$entry"
  dest="$worktree/$entry"
  # Both declines below are reported rather than silent: a mistyped entry is
  # otherwise indistinguishable from a correctly configured repo, since either
  # way the hook copies nothing and says nothing.
  if [ ! -e "$src" ]; then
    missing="$missing $entry"
    continue
  fi
  # Present already - a tracked path, or a second entry into the same worktree.
  # Never overwritten: the worktree's copy is the one being worked in. The
  # check is per entry, so a directory here is declined with its contents.
  if [ -e "$dest" ]; then
    present="$present $entry"
    continue
  fi

  mkdir -p "${dest%/*}" 2>/dev/null || { skipped="$skipped $entry"; continue; }
  # -p for the mode: a credentials file set to 600 in the base clone must not
  # widen on the way in. -R so a directory entry works the same as a file.
  cp -Rp "$src" "$dest" 2>/dev/null || { skipped="$skipped $entry"; continue; }
  copied="$copied $entry"
done <<EOF
$dump
EOF

[ -n "$copied$present$missing$skipped" ] || exit 0

msg="Copied into the worktree from $base:${copied:- nothing}"
[ -n "$present" ] && msg="$msg. Already in the worktree, left alone whole:$present"
[ -n "$missing" ] && msg="$msg. Not in the base clone:$missing"
[ -n "$skipped" ] && msg="$msg. Skipped, not a relative path inside the repo:$skipped"
jq -cn --arg m "$msg" '{systemMessage: $m, suppressOutput: true}'
exit 0
