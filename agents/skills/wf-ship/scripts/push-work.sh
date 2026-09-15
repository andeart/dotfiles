#!/usr/bin/env bash
set -euo pipefail

# wf-ship's push, run chained after commit.sh. Feature mode pushes the current
# branch and looks up its pull request. Move mode, for a ship from the default
# branch, cuts <branch> at the default branch's upstream, cherry-picks the
# unpushed commits onto it, and pushes it.
#
# Output, read by position:
#   1. key=value lines, every one of them this script's own text;
#   2. when pushed_total is printed, `pushed<<<` and exactly pushed_shown paths,
#      the first of pushed_total, at most 100;
#   3. on a pull request hit, `pr_first_line<<<` and one line;
#   4. when a push or a failed cherry-pick ran, `git_log<<<` and its output,
#      control bytes removed, to the end. When nothing was pushed and the
#      lookup found no pull request, `gh_log<<<` and the lookup's error,
#      control bytes removed, to the end, instead.
# Hooks print on stdout as well as stderr, so each git command that runs one or
# prints repo text has both streams captured.

usage() {
  cat <<'EOF'
Usage: push-work.sh --default <main|master> [--move-to <branch>]

Feature mode, --default alone: pushes the current branch, which must not be
the default branch, and looks up its pull request.

Move mode, with --move-to: creates <branch> at the default branch's upstream,
cherry-picks the default branch's unpushed commits onto it, and pushes it.
<branch> matches ^[A-Za-z0-9][A-Za-z0-9-]*$ and must not exist yet.

Exit status:
  0  output is complete; route on the printed values
  2  usage error; nothing was created or pushed
EOF
}

die() {
  echo "push-work: $*" >&2
  exit 1
}

refuse() {
  usage >&2
  exit 2
}

strip_controls() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

case "${BASH_SOURCE[0]}" in
  */*) lookup="${BASH_SOURCE[0]%/*}" ;;
  *) lookup=. ;;
esac
lookup="$lookup/pr-lookup.sh"

# The path cap keeps a large push's later sections inside a result the Bash
# tool returns inline rather than behind a saved file's preview.
pushed_max=100
mode= default= move_to= paths= docs_only= pushed_total= pushed_shown= git_log= lookup_out= gh_log=
have_paths=no have_log=no have_first=no have_gh_log=no

# record_paths <base>: the paths from the merge base of <base> and HEAD. Three
# dots, so a default branch that moved adds none of its own paths.
# Each flag pins the listing against config:
#   --no-relative             diff.relative, from a subdirectory, lists only
#                             that directory's paths, prefix stripped
#   --ignore-submodules=none  diff.ignoreSubmodules=all drops a gitlink change
#   -M                        diff.renames=false lists a move as two paths
# A move is one line, listed by its new path, and docs_only reads both of its
# paths, so a move into docs/ is not docs-only. pushed_total and docs_only read
# every line; paths keeps the first pushed_max.
# Git quotes a path holding a tab, non-ASCII or control byte, so a tab only
# separates fields, a quoted path under docs/ opens with "docs/, and a path
# that itself opens with a quote is printed as "\"...
record_paths() {
  local out counts
  out=$(git diff --name-status --no-relative --ignore-submodules=none -M "$1...HEAD" \
    | awk -F '\t' -v max="$pushed_max" '
    NR <= max { keep = keep "\n" $NF }
    { for (i = 2; i <= NF; i++) if ($i !~ /^"?docs\//) other = 1 }
    END { printf "%d %s%s", NR, ((NR && !other) ? "yes" : "no"), keep }')
  counts=${out%%$'\n'*}
  pushed_total=${counts%% *}
  docs_only=${counts#* }
  pushed_shown=$(( pushed_total < pushed_max ? pushed_total : pushed_max ))
  paths=
  [ "$pushed_shown" -eq 0 ] || paths=${out#*$'\n'}
  have_paths=yes
}

push_head() {
  local push_exit=0
  git_log=$(git push -u origin HEAD 2>&1) || push_exit=$?
  have_log=yes
  echo "pushed_total=$pushed_total"
  echo "pushed_shown=$pushed_shown"
  echo "pushed_docs_only=$docs_only"
  echo "push_exit=$push_exit"
  return "$push_exit"
}

feature() {
  local ref base upstream unpushed pushed=yes
  # The full ref: with a tag named like the branch, --short prints heads/<name>
  # and the comparison would pass on the default branch itself.
  ref=$(git symbolic-ref --quiet HEAD) || refuse
  [ "$ref" != "refs/heads/$default" ] || refuse
  if base=$(git rev-parse --verify --quiet '@{upstream}'); then
    upstream=yes
  else
    upstream=no
    base=$(git rev-parse --verify "refs/remotes/origin/$default")
  fi
  unpushed=$(git rev-list --count "$base..HEAD")
  echo "upstream=$upstream"
  echo "unpushed_total=$unpushed"
  if [ "$upstream" = yes ] && [ "$unpushed" -eq 0 ]; then
    pushed=no
    echo 'pushed=no'
  else
    record_paths "$base"
    push_head || return 0
  fi
  # A trailing `.` keeps the lookup's trailing newlines, so an empty first
  # line still counts as a line.
  lookup_out=$(bash "$lookup"; echo .)
  lookup_out=${lookup_out%.}
  if [ "${lookup_out%%=*}" = pr_url ] \
    && [ "$(printf '%s' "$lookup_out" | awk 'NR == 3')" = 'pr_first_line<<<' ]; then
    printf '%s' "$lookup_out" | awk 'NR <= 2'
    have_first=yes
    return 0
  fi
  echo 'pr=none'
  # Where nothing was pushed, pr=none ends the ship, and gh's error is what
  # tells a failed lookup from a branch with no pull request. After a push,
  # gh pr create reports its own error.
  [ "$pushed" = yes ] || have_gh_log=yes
  # Output off pr-lookup's contract, as a partial sync can leave, is a failed
  # lookup too, never an exit: the push may already have landed.
  case $lookup_out in
    pr=none$'\n''gh_log<<<'$'\n'*) gh_log=${lookup_out#pr=none$'\n''gh_log<<<'$'\n'} ;;
    *) gh_log="push-work: unexpected pr-lookup output"$'\n'"$lookup_out" ;;
  esac
}

move() {
  local branch=$move_to up out cherry_pick_exit=0
  [[ $branch =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || refuse
  if git show-ref --verify --quiet "refs/heads/$branch"; then
    refuse
  fi
  # The short name: refs/heads/main@{upstream} does not resolve, and a tag named
  # like the branch does not change what main@{upstream} resolves to.
  up=$(git rev-parse --verify --quiet "$default@{upstream}") || refuse
  # One step: a checkout that fails, say over an untracked file the upstream
  # tracks, creates no branch, so a re-ship can take the same name.
  out=$(git checkout -q -b "$branch" "$up" 2>&1) || die "$out"
  git_log=$(git cherry-pick "$up..refs/heads/$default" 2>&1) || cherry_pick_exit=$?
  echo "cherry_pick_exit=$cherry_pick_exit"
  if [ "$cherry_pick_exit" -ne 0 ]; then
    have_log=yes
    return 0
  fi
  record_paths "$up"
  push_head || return 0
}

work() {
  set -e
  [ -f "$lookup" ] || die "missing $lookup - run 'dotfiles push' to sync the skills"
  # The mode comes from the argument count, never from an empty value: an empty
  # --move-to is a refused name, not feature mode.
  case "$#:${1-}:${3-}" in
    2:--default:) mode=feature default=$2 ;;
    4:--default:--move-to) mode=move default=$2 move_to=$4 ;;
    *) refuse ;;
  esac
  case $default in main|master) ;; *) refuse ;; esac

  if [ "$mode" = feature ]; then feature; else move; fi

  if [ "$have_paths" = yes ]; then
    echo 'pushed<<<'
    [ "$pushed_shown" -eq 0 ] || printf '%s\n' "$paths"
  fi
  if [ "$have_first" = yes ]; then
    echo 'pr_first_line<<<'
    printf '%s' "$lookup_out" | awk 'NR == 4'
  fi
  if [ "$have_log" = yes ]; then
    echo 'git_log<<<'
    [ -z "$git_log" ] || printf '%s\n' "$git_log" | strip_controls
  fi
  if [ "$have_gh_log" = yes ]; then
    echo 'gh_log<<<'
    [ -z "$gh_log" ] || printf '%s\n' "${gh_log%$'\n'}" | strip_controls
  fi
}

# Every other git call's stderr is held, and printed to stderr only when the
# script fails. `set +e` around the capture, never `|| st=$?`: bash 5 ignores
# `set -e` inside a function called from a `||` list, command substitution
# included.
exec 3>&1
set +e
err=$(work "$@" 2>&1 >&3 3>&-)
st=$?
set -e
exec 3>&-
if [ "$st" -ne 0 ]; then
  [ -z "$err" ] || printf '%s\n' "$err" >&2
  exit "$st"
fi
