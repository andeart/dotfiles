#!/usr/bin/env bash
set -euo pipefail

# wf-ship's staging step. It stops when an operation is in progress, when the
# index has unmerged entries, or when an untracked directory adds more than one
# file. If not, it stages in one pass the tracked changes and all untracked
# paths without a leftover suffix. Then it reports gitlinks, the staged count
# and the untracked paths that stay. When the ship continues to a commit, it
# runs git-conventions/scripts/gather.sh for the commit message.
#
# Output, read by position:
#   1. key=value lines. The script writes their text, but `gitlink=` holds a
#      path in the quoted form of git, which keeps the path on one line;
#   2. when both adds exit 0, `residue<<<` and exactly residue_shown paths;
#   3. when the gather runs, `gather<<<` and its output to the end;
#   4. when an add fails, `add_log<<<` and the output of the adds to the end.
# All other repo-controlled text, such as paths, patch lines and git messages,
# is only in sections 2 to 4, so no line of it reads as a key.

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

# The script does this check before it stages, so a partial install stops with
# no change to the index. resolve-wf-config.sh uses the same locator for
# base-clone.sh.
case "${BASH_SOURCE[0]}" in
  */*) gather="${BASH_SOURCE[0]%/*}" ;;
  *) gather=. ;;
esac
gather="$gather/../../git-conventions/scripts/gather.sh"
[ -f "$gather" ] || die "missing $gather - run 'dotfiles push' to sync the skills"

stage() {
  set -e
  local gd f inprogress= untracked_collapsed untracked_total out add_log= add_tracked_exit add_rest_exit
  local raw gitlinks staged_total residue residue_total residue_shown residue_paths
  local gather_ran=no gather_exit=0 gather_out=
  # The pathspec of the second add. The untracked counts use it too.
  local rest=(':(top,exclude,icase)*.orig' ':(top,exclude,icase)*.rej' ':(top,exclude,icase)*.bak'
              ':(top,exclude,icase)*.swp' ':(top,exclude,icase)*.swo' ':(top,exclude,icase)*~' ':/')

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

  # Count the paths that the second add stages two times: first with each fully
  # untracked directory as one path, then with each file. A higher file count
  # shows a directory that expands. The counts read only untracked paths, before
  # the adds, so status, submodule and rename settings do not change them, and a
  # stop stages nothing. A directory that holds only leftovers or ignored files
  # is in neither count.
  untracked_collapsed=$(git ls-files -o --exclude-standard --directory --no-empty-directory -- "${rest[@]}" | awk 'END { print NR }')
  untracked_total=$(git ls-files -o --exclude-standard -- "${rest[@]}" | awk 'END { print NR }')
  echo "untracked_collapsed=$untracked_collapsed"
  echo "untracked_total=$untracked_total"
  if [ "$untracked_total" -gt "$untracked_collapsed" ]; then
    return 0
  fi

  # The script captures the status of each add, so set -e does not stop the
  # script: wf-ship reads both exit lines to report a part-staged index. The
  # script also captures the output of each add, because git prints repo paths
  # raw in its warnings.
  add_tracked_exit=0
  out=$(git add -u 2>&1) || add_tracked_exit=$?
  [ -z "$out" ] || add_log="$out"$'\n'
  echo "add_tracked_exit=$add_tracked_exit"
  add_rest_exit=0
  out=$(git add -- "${rest[@]}" 2>&1) || add_rest_exit=$?
  [ -z "$out" ] || add_log="$add_log$out"$'\n'
  echo "add_rest_exit=$add_rest_exit"

  # --no-relative: with diff.relative=true, from a subdirectory, the raw read
  # removes all paths outside that directory, also a gitlink at the root.
  # --ignore-submodules=none: with diff.ignoreSubmodules=all, the raw read
  # removes a staged gitlink, and the gitlink stop does not occur.
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

  # Use awk, not `head -n 10`: head exits after ten lines, git then gets
  # SIGPIPE, and pipefail stops the script with no message on stderr.
  residue=$(git ls-files -o --exclude-standard --full-name -- :/ \
    | awk 'NR <= 10 { keep = keep "\n" $0 } END { printf "%d%s", NR, keep }')
  residue_total=${residue%%$'\n'*}
  residue_shown=$(( residue_total < 10 ? residue_total : 10 ))
  residue_paths=
  [ "$residue_shown" -eq 0 ] || residue_paths=${residue#*$'\n'}

  # The gather runs only when wf-ship commits. A ship that stops on a gitlink
  # does not put the patch of the embedded repository into context.
  if [ "$staged_total" -gt 0 ] && [ -z "$gitlinks" ]; then
    gather_ran=yes
    gather_out=$(bash "$gather" 2>&1) || gather_exit=$?
  fi

  echo "residue_total=$residue_total"
  echo "residue_shown=$residue_shown"
  [ "$gather_ran" = no ] || echo "gather_exit=$gather_exit"
  echo 'residue<<<'
  [ "$residue_shown" -eq 0 ] || printf '%s\n' "$residue_paths"
  # Remove ESC, because wf-ship shows this section when the gather fails. Keep
  # CR: a CRLF-to-LF change shows as CR in the patch.
  if [ "$gather_ran" = yes ]; then
    echo 'gather<<<'
    [ -z "$gather_out" ] || printf '%s\n' "$gather_out" | LC_ALL=C tr -d '\033'
  fi
}

# The script holds the stderr of all other git commands and prints it to stderr
# only when the script fails. The Bash tool merges stderr into stdout in write
# order, so without this capture a warning with a repo path can show between
# the key lines. Use `set +e` around the capture, not `|| st=$?`: bash 5 ignores
# `set -e` in a function that runs as part of a `||` list, also in a command
# substitution.
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
