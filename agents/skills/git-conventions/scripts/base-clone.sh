#!/usr/bin/env bash
#
# The base clone of a linked git worktree, found from the filesystem alone.
#
# Three callers source this file: wf-conventions/scripts/resolve-wf-config.sh,
# work-item-conventions/scripts/resolve-tracker.sh and
# claude/hooks/copy-into-worktree.sh. One copy of the registration check below
# serves all three. A source puts POINTER_MAX and base_clone, both unprefixed,
# into the caller's shell.
#
# Each caller finds this file relative to its own location, below a directory
# the agent writes to. One `dotfiles push` ships the helper and its callers, so
# this file is trusted as far as its caller is, and no further.
#
# The callers find it with `${BASH_SOURCE[0]%/*}` and not with $(dirname ...),
# which costs a fork and an exec on every run. The two forms differ only for a
# path that has no slash, which is what a caller run from its own directory
# gets, so each caller falls back to `.` for that case.
#
# WARNING: this file must only define and return. Set no shell options, keep no
# state, and run nothing at load. The two resolvers source it and then print
# key=value lines that a skill reads by field, so a print at load makes a false
# `config_path=` line before the true one. copy-into-worktree.sh sources it into
# the shell whose stdout is the hook's JSON, and runs without `-e` so that it
# can fail open. A source gives no containment. tests/resolve-wf-config.bats
# grades both halves.

# The limit on both reads in base_clone. No path a filesystem accepts reaches
# 4096 bytes.
POINTER_MAX=4096

# base_clone <root>: print the base clone of the linked worktree at <root>, or
# print nothing. Each branch that declines returns 0, because the callers read
# this function through a command substitution under `set -e`.
#
# This function prints, while the lookups in the two resolvers assign. It runs
# at most once per run, so the subshell costs less than a contract that three
# callers must change together.
#
# A FILE at root/.git is the whole of what separates a linked worktree from an
# ordinary clone.
#
# root/.git is attacker-controlled, as .wf.yml is, and a regular file of any
# size passes an is-a-file test. Four limits bound both reads:
#  - [ -f ] rejects a directory, a FIFO, a device and a missing file;
#  - POINTER_MAX limits the length;
#  - a nonzero read status is accepted, because a file with no final newline
#    returns 1 with the value set;
#  - the brace group discards stderr, because a mode-000 regular file passes
#    [ -f ] and then fails at the redirect. The braces put the redirect in the
#    correct order. A bare `read ... < file 2>/dev/null` still prints.
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
  # A submodule path has a `/modules/` segment and fails this test. A bare repo
  # at the usual `<name>.git` has no `/.git/` segment and also fails.
  case "$ptr" in
    */.git/worktrees/?*) ;;
    *) return 0 ;;
  esac
  # The longest match, so a deeper `.git/worktrees` cannot leave a slash in the
  # name. A name that holds a slash does not name a registration.
  name="${ptr##*/.git/worktrees/}"
  case "$name" in
    */*) return 0 ;;
  esac
  # The test above reads the shape of the pointer. This test reads the
  # registration. git writes the relationship both ways, so <ptr>/gitdir names
  # this worktree's own .git. A pointer whose other half is absent or stale
  # declines here: a deleted base clone, a moved base clone, or a copied tree.
  # Without this test, the caller reads an unrelated config and runs its
  # verify.commands.
  #
  # This is not an authenticity check. A writer who can write root/.git can also
  # write the matching gitdir. It does not have to be one, because that writer
  # can put the config in root itself.
  [ -f "$ptr/gitdir" ] || return 0
  backref=""
  { IFS= read -r -n "$POINTER_MAX" backref < "$ptr/gitdir"; } 2>/dev/null || :
  [ -n "$backref" ] || return 0
  case "$backref" in
    /*) ;;
    *) backref="$ptr/$backref" ;;
  esac
  # -ef is a builtin in /bin/bash 3.2 and in zsh, and it stats both paths. So
  # the kernel resolves a relative back-reference, each `..` in it, and each
  # symlink on the two sides. No step before this one normalises a path.
  [ "$backref" -ef "$root/.git" ] || return 0
  # /.git/worktrees/<name> is three segments, removed one at a time. The
  # non-empty test guards `gitdir: /.git/worktrees/x`, which strips to nothing
  # and makes the caller stat /.wf.yml at the filesystem root.
  base="${ptr%/*}"; base="${base%/*}"; base="${base%/*}"
  [ -n "$base" ] || return 0
  # Resolved, and not spelled: three skills show this path beside the
  # verify.commands they run, so `<trusted>/.git/worktrees/../../../evil` must
  # not read as the trusted clone. This normalises the answer only, and never
  # the -ef test above. A failed cd declines. `CDPATH=` keeps a relative base
  # off CDPATH.
  base="$(CDPATH= cd -- "$base" 2>/dev/null && pwd -P)" || base=""
  [ -n "$base" ] || return 0
  # A directory name can hold any byte that the pointer read accepts. The skills
  # echo this value into a key=value block, where a newline makes a second
  # setting, and a CR or an ESC rewrites the line that a reader sees. One
  # pattern rejects the whole class.
  case "$base" in
    *[[:cntrl:]]*) return 0 ;;
  esac
  printf '%s\n' "$base"
}
