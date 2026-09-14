#!/usr/bin/env bash
set -euo pipefail

# wf-ship's commit: commits what is staged, with the message read from stdin.
# Silent on success, so a command chained after it with `&&` owns the output
# from its first line. A hook can echo repo-controlled text, such as a file
# name that reads as a key, so the commit's output is captured and printed only
# on failure: `commit_log<<<`, then that output with control bytes removed, to
# the end.

usage() {
  cat <<'EOF'
Usage: commit.sh < message

Takes no arguments. Commits the index with the message on stdin. Prints
nothing on success. On failure prints `commit_log<<<` and the commit's output,
hooks included.

Exit status:
  0  committed
  1  the commit failed; the index is as it was
  2  usage error
EOF
}

if [ "$#" -ne 0 ]; then
  usage >&2
  exit 2
fi

strip_controls() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

st=0
out=$(git commit -q -F - 2>&1) || st=$?
if [ "$st" -ne 0 ]; then
  echo 'commit_log<<<'
  [ -z "$out" ] || printf '%s\n' "$out" | strip_controls
  exit 1
fi
