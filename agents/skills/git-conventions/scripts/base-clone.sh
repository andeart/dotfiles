#!/usr/bin/env bash
#
# The base clone of a linked git worktree, resolved from the filesystem alone.
#
# Sourced by both resolvers that need it - wf-conventions/scripts/resolve-wf-config.sh
# and work-item-conventions/scripts/resolve-tracker.sh - so the back-reference
# check below has one copy. That check is a trust boundary, not a shape test:
# without it any .git file naming a directory would have that directory's
# config read, and its verify.commands executed.
#
# Sourcing this puts two unprefixed globals in the caller's shell: POINTER_MAX
# and base_clone. A third consumer inherits both silently.
#
# Each resolver's trust boundary runs through this file, which they resolve
# relative to their own location, under a directory the agent itself writes to.
# What makes that sound is that helper and callers ship in one `dotfiles push`,
# so this is trusted exactly as far as its caller already is - not further.
#
# Defines and returns. No shell options, no state, nothing executed at load.

# Caps both reads in base_clone. No path a filesystem accepts reaches 4096.
POINTER_MAX=4096

# base_clone <root>: print the base clone of the linked worktree at <root>, or
# nothing. Every declining branch returns 0 explicitly; the caller reads this
# through a command substitution under set -e.
#
# root/.git being a FILE is the whole of what separates a linked worktree from
# an ordinary clone.
#
# root/.git is attacker-controlled under the same model .wf.yml is, and a
# regular file passes an is-a-file test at any size, so both reads are bounded
# four ways: [ -f ] rejects a directory, FIFO, device and missing file;
# POINTER_MAX caps the length; a nonzero read status is tolerated because a
# file with no trailing newline returns 1 with the value set; and the brace
# group's stderr is discarded because a mode-000 regular file passes [ -f ] and
# then fails at the redirect. The braces place that redirect - a bare
# `read ... < file 2>/dev/null` applies them in the wrong order and still
# prints.
base_clone() {
  local root="$1" line ptr name backref base
  [ -f "$root/.git" ] || return 0
  line=""
  { IFS= read -r -n "$POINTER_MAX" line < "$root/.git"; } 2>/dev/null || :
  case "$line" in
    "gitdir: "?*) ptr="${line#gitdir: }" ;;
    *) return 0 ;;
  esac
  case "$ptr" in
    /*) ;;
    *) ptr="$root/$ptr" ;;
  esac
  # A submodule's `/modules/` segment fails this, and so does a bare repo under
  # the conventional `<name>.git`, whose segment leaves no `/.git/` to match.
  case "$ptr" in
    */.git/worktrees/?*) ;;
    *) return 0 ;;
  esac
  # Longest match, so a `.git/worktrees` deeper in the path cannot leave a
  # slash in the name. A name carrying one does not name a registration.
  name="${ptr##*/.git/worktrees/}"
  case "$name" in
    */*) return 0 ;;
  esac
  # The pointer's shape is a string test; this is the trust boundary. git
  # registers the relationship both ways, and <ptr>/gitdir holds the path back
  # to this worktree's own .git. Without this check, any .git file naming a
  # directory would have that directory's verify.commands executed by three
  # skills.
  [ -f "$ptr/gitdir" ] || return 0
  backref=""
  { IFS= read -r -n "$POINTER_MAX" backref < "$ptr/gitdir"; } 2>/dev/null || :
  [ -n "$backref" ] || return 0
  case "$backref" in
    /*) ;;
    *) backref="$ptr/$backref" ;;
  esac
  # -ef is a builtin in both /bin/bash 3.2 and zsh and stats both paths, so the
  # kernel resolves a relative back-reference, any `..` in it and any symlink on
  # either side. Nothing up to here normalises a path.
  [ "$backref" -ef "$root/.git" ] || return 0
  # /.git/worktrees/<name> is three segments, stripped one at a time. The
  # non-empty check guards `gitdir: /.git/worktrees/x`, which strips to nothing
  # and would leave the caller statting /.wf.yml at the filesystem root.
  base="${ptr%/*}"; base="${base%/*}"; base="${base%/*}"
  [ -n "$base" ] || return 0
  # Resolved, not spelled: three skills show this path beside the
  # verify.commands they execute, and `<trusted>/.git/worktrees/../../../evil`
  # must not read as the trusted clone. This normalises the answer only, never
  # the -ef above. A failed cd declines; `CDPATH=` keeps a relative base off it.
  base="$(CDPATH= cd -- "$base" 2>/dev/null && pwd -P)" || base=""
  [ -n "$base" ] || return 0
  # A directory name stops at no byte the pointer read catches. In the
  # key=value block the skills echo this into, a newline forges another setting
  # and a CR or ESC rewrites the line a reader sees; the whole class costs the
  # same one pattern.
  case "$base" in
    *[[:cntrl:]]*) return 0 ;;
  esac
  printf '%s\n' "$base"
}
