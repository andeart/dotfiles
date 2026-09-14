#!/usr/bin/env bash
set -euo pipefail

# wf-ship's staging step. Refuses when an operation is in progress or the index
# holds unmerged entries. Otherwise stages tracked changes, and every untracked
# path except the leftover suffixes, in one pass. Then reports gitlinks, what it
# staged and the untracked paths it left and, when the ship goes on to commit,
# runs git-conventions/scripts/gather.sh for the commit message.
#
# Output, read by position:
#   1. key=value lines, this script's own text, except that `gitlink=` carries
#      a path in git's quoted form, which keeps it on one line;
#   2. when both adds exited 0, `residue<<<` and exactly residue_shown paths;
#   3. when the gather ran, `gather<<<` and its output to the end;
#   4. when an add failed, `add_log<<<` and the adds' output to the end.
# Other repo-controlled text - paths, patch lines, git's messages - appears only
# in sections 2 to 4, so no line of it is read as a key.

wf_usage() {
  cat <<'EOF'
Usage: stage-work.sh

Takes no arguments. Stages the work in the current repository and writes
`key=value` lines to stdout, then the residue paths after `residue<<<`, then
the commit-message gather after `gather<<<` or the adds' output after
`add_log<<<`.

Exit status:
  0  output is complete; route on the printed values
  2  usage error
EOF
}

die() {
  echo "stage-work: $*" >&2
  exit 1
}

if [ "$#" -ne 0 ]; then
  wf_usage >&2
  exit 2
fi

# Checked before anything is staged, so a partial install stops with the index
# untouched. The same locator as resolve-wf-config.sh's for base-clone.sh.
case "${BASH_SOURCE[0]}" in
  */*) gather="${BASH_SOURCE[0]%/*}" ;;
  *) gather=. ;;
esac
gather="$gather/../../git-conventions/scripts/gather.sh"
[ -f "$gather" ] || die "missing $gather - run 'dotfiles push' to sync the skills"

stage() {
  set -e
  local gd f inprogress= porcelain_total out add_log= add_tracked_exit add_rest_exit
  local raw gitlinks staged_total residue residue_total residue_shown residue_paths
  local gather_ran=no gather_exit=0 gather_out=

  gd=$(git rev-parse --git-dir)
  for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
    if [ -e "$gd/$f" ]; then
      inprogress=$f
      break
    fi
  done
  if [ -n "$inprogress" ] || [ -n "$(git ls-files -u)" ]; then
    echo "blocked=${inprogress:-unmerged-index}"
    return 0
  fi
  echo 'blocked=no'

  # --untracked-files=normal, so status.showUntrackedFiles cannot expand or hide
  # the untracked directories wf-ship's staged_total stop compares against.
  # --ignore-submodules=none: under diff.ignoreSubmodules=all, status hides a
  # bumped gitlink, which would let staged_total exceed this count and trip the
  # expanded-directory stop over a change the stop was never meant to catch.
  porcelain_total=$(git status --porcelain --untracked-files=normal --ignore-submodules=none | awk 'END { print NR }')
  echo "porcelain_total=$porcelain_total"

  # Each add's status is captured, so set -e does not stop the script: wf-ship
  # reads both exit lines to report a part-staged index. Each add's output is
  # captured too, because git prints repo paths raw in its warnings.
  add_tracked_exit=0
  out=$(git add -u 2>&1) || add_tracked_exit=$?
  [ -z "$out" ] || add_log="$out"$'\n'
  echo "add_tracked_exit=$add_tracked_exit"
  add_rest_exit=0
  out=$(git add -- ':(top,exclude,icase)*.orig' ':(top,exclude,icase)*.rej' ':(top,exclude,icase)*.bak' \
                   ':(top,exclude,icase)*.swp' ':(top,exclude,icase)*.swo' ':(top,exclude,icase)*~' ':/' 2>&1) \
    || add_rest_exit=$?
  [ -z "$out" ] || add_log="$add_log$out"$'\n'
  echo "add_rest_exit=$add_rest_exit"

  # --no-relative: under diff.relative=true, run from a subdirectory, the raw
  # read drops every path outside it, a gitlink at the root included.
  # --ignore-submodules=none: under diff.ignoreSubmodules=all, the raw read
  # drops a staged gitlink entirely, and the gitlink stop never fires.
  raw=$(git diff --cached --raw --no-relative --ignore-submodules=none)
  gitlinks=$(printf '%s' "$raw" | awk '
    $1 == ":000000" && $2 == "160000" { print "gitlink=" substr($0, index($0, "\t") + 1) }')
  [ -z "$gitlinks" ] || printf '%s\n' "$gitlinks"
  staged_total=$(printf '%s' "$raw" | awk 'END { print NR }')
  if [ "$staged_total" -gt 0 ]; then echo 'staged=yes'; else echo 'staged=no'; fi
  echo "staged_total=$staged_total"

  if [ "$add_tracked_exit" -ne 0 ] || [ "$add_rest_exit" -ne 0 ]; then
    echo 'add_log<<<'
    printf '%s' "$add_log"
    return 0
  fi

  # awk, not `head -n 10`: head exits after ten lines, git then gets SIGPIPE,
  # and pipefail stops the script with no message on stderr.
  residue=$(git ls-files -o --exclude-standard --full-name -- :/ \
    | awk 'NR <= 10 { keep = keep "\n" $0 } END { printf "%d%s", NR, keep }')
  residue_total=${residue%%$'\n'*}
  residue_shown=$(( residue_total < 10 ? residue_total : 10 ))
  residue_paths=
  [ "$residue_shown" -eq 0 ] || residue_paths=${residue#*$'\n'}

  # The conditions under which wf-ship commits. A ship that stops never carries
  # an expanded directory's or an embedded repository's patch into context.
  if [ "$staged_total" -gt 0 ] && [ -z "$gitlinks" ] && [ "$staged_total" -le "$porcelain_total" ]; then
    gather_ran=yes
    gather_out=$(bash "$gather" 2>&1) || gather_exit=$?
  fi

  echo "residue_total=$residue_total"
  echo "residue_shown=$residue_shown"
  [ "$gather_ran" = no ] || echo "gather_exit=$gather_exit"
  echo 'residue<<<'
  [ "$residue_shown" -eq 0 ] || printf '%s\n' "$residue_paths"
  if [ "$gather_ran" = yes ]; then
    echo 'gather<<<'
    [ -z "$gather_out" ] || printf '%s\n' "$gather_out"
  fi
}

# Every other git call's stderr is held, and printed to stderr only when the
# script fails. The Bash tool merges stderr into stdout in write order, so a
# warning naming a repo path would otherwise land among the key lines.
# `set +e` around the capture, never `|| st=$?`: bash 5 ignores `set -e` inside
# a function called from a `||` list, command substitution included.
exec 3>&1
set +e
err=$(stage 2>&1 >&3 3>&-)
st=$?
set -e
exec 3>&-
if [ "$st" -ne 0 ]; then
  [ -z "$err" ] || printf '%s\n' "$err" >&2
  exit "$st"
fi
