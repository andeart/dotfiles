#!/usr/bin/env bash
set -euo pipefail

# wf-ship's push, run chained after its commit. Feature mode pushes the current
# branch and looks up its pull request. Move mode, for a ship from the default
# branch, cuts <branch> at the default branch's upstream, cherry-picks the
# unpushed commits onto it, and pushes it.
#
# Output, read by position:
#   1. `push_work=begin`, the first stdout line. A commit chained in front
#      prints its hook output first, so keys are read only from here on;
#   2. key=value lines, every one of them this script's own text;
#   3. when pushed_total is printed, `pushed<<<` and exactly that many paths;
#   4. on a pull request hit, `pr_first_line<<<` and one line;
#   5. when a push or a failed cherry-pick ran, `git_log<<<` and its output,
#      control bytes removed, to the end.
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

mode= default= move_to= paths= docs_only= pushed_total= git_log= lookup_out=
have_paths=no have_log=no have_first=no

# all_under_docs: reads NUL-terminated paths on stdin and prints yes when there
# is at least one and every one sits under docs/, otherwise no. A function
# rather than a loop inline in $(...): /bin/bash 3.2 cannot parse a case
# pattern's `)` inside a command substitution.
all_under_docs() {
  local n=0 answer=yes p
  while IFS= read -r -d '' p; do
    n=$((n + 1))
    case $p in
      docs/*) ;;
      *) answer=no ;;
    esac
  done
  [ "$n" -gt 0 ] || answer=no
  echo "$answer"
}

# record_paths <base>: the paths from the merge base of <base> and HEAD. Three
# dots, so a default branch that moved adds none of its own paths.
# --no-relative: under diff.relative=true, from a subdirectory, --name-only
# lists only that directory's paths, prefix stripped.
record_paths() {
  paths=$(git diff --name-only --no-relative "$1...HEAD")
  pushed_total=$(printf '%s' "$paths" | awk 'END { print NR }')
  # -z, because --name-only quotes a non-ASCII path, and "docs/\303\251.md"
  # fails a docs/ prefix test.
  docs_only=$(git diff --name-only -z --no-relative "$1...HEAD" | all_under_docs)
  have_paths=yes
}

push_head() {
  local push_exit=0
  git_log=$(git push -u origin HEAD 2>&1) || push_exit=$?
  have_log=yes
  echo "pushed_total=$pushed_total"
  echo "pushed_docs_only=$docs_only"
  echo "push_exit=$push_exit"
  return "$push_exit"
}

feature() {
  local ref base upstream unpushed
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
    echo 'pushed=no'
  else
    record_paths "$base"
    push_head || return 0
  fi
  # A trailing `.` keeps the lookup's trailing newlines, so an empty first
  # line still counts as a line.
  lookup_out=$(bash "$lookup"; echo .)
  lookup_out=${lookup_out%.}
  case $lookup_out in
    pr=none$'\n'*)
      echo 'pr=none'
      ;;
    pr_url=*)
      [ "$(printf '%s' "$lookup_out" | awk 'NR == 3')" = 'pr_first_line<<<' ] \
        || die 'unexpected pr-lookup output'
      printf '%s' "$lookup_out" | awk 'NR <= 2'
      have_first=yes
      ;;
    *)
      die 'unexpected pr-lookup output'
      ;;
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
  out=$(git branch "$branch" "$up" 2>&1) || die "$out"
  out=$(git checkout "$branch" 2>&1) || die "$out"
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
  echo 'push_work=begin'
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
    [ "$pushed_total" -eq 0 ] || printf '%s\n' "$paths"
  fi
  if [ "$have_first" = yes ]; then
    echo 'pr_first_line<<<'
    printf '%s' "$lookup_out" | awk 'NR == 4'
  fi
  if [ "$have_log" = yes ]; then
    echo 'git_log<<<'
    [ -z "$git_log" ] || printf '%s\n' "$git_log" | strip_controls
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
