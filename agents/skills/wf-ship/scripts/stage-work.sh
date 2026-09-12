#!/usr/bin/env bash
set -euo pipefail

# wf-ship's staging step. Refuses over an operation in progress or an unmerged
# index; otherwise stages tracked edits and every untracked path except the
# leftover suffixes in one pass, then reports gitlinks, what was staged, and the
# untracked paths left behind. Every `key=` line precedes `residue<<<`; what
# follows it is paths, never keys.

wf_usage() {
  cat <<'EOF'
Usage: stage-work.sh

Takes no arguments. Stages the work in the current repository and writes
`key=value` lines to stdout, then the residue paths after `residue<<<`.

Exit status:
  0  reached its output; route on the printed values
  2  usage error
EOF
}

if [ "$#" -ne 0 ]; then
  wf_usage >&2
  exit 2
fi

gd=$(git rev-parse --git-dir)
inprogress=
for f in MERGE_HEAD CHERRY_PICK_HEAD REVERT_HEAD rebase-merge rebase-apply sequencer; do
  [ -e "$gd/$f" ] && { inprogress=$f; break; }
done
if [ -n "$inprogress" ] || [ -n "$(git ls-files -u)" ]; then
  echo "blocked=${inprogress:-unmerged-index}"
else
  echo 'blocked=no'
  # Each add's status is captured rather than left to set -e: wf-ship needs both
  # exit lines to tell a part-staged index from a run cut short.
  add_tracked_exit=0; git add -u || add_tracked_exit=$?
  echo "add_tracked_exit=$add_tracked_exit"
  add_rest_exit=0
  git add -- ':(top,exclude,icase)*.orig' ':(top,exclude,icase)*.rej' ':(top,exclude,icase)*.bak' \
             ':(top,exclude,icase)*.swp' ':(top,exclude,icase)*.swo' ':(top,exclude,icase)*~' ':/' \
    || add_rest_exit=$?
  echo "add_rest_exit=$add_rest_exit"
  git diff --cached --raw | awk '
    { n++ }
    $1 == ":000000" && $2 == "160000" { print "gitlink=" substr($0, index($0, "\t") + 1) }
    END { print "staged=" (n ? "yes" : "no"); print "staged_total=" (n + 0) }'
  if [ "$add_tracked_exit" -eq 0 ] && [ "$add_rest_exit" -eq 0 ]; then
    # awk rather than `head -n 10`: head exits after ten lines, and under
    # pipefail the SIGPIPE that leaves git with stops the script with nothing on
    # stderr.
    git ls-files -o --exclude-standard --full-name -- :/ \
      | awk 'NR <= 10 { keep = keep $0 "\n" }
             END { print "residue_total=" NR; print "residue<<<"; printf "%s", keep }'
  fi
fi
