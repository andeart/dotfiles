#!/usr/bin/env bash
set -euo pipefail

# wf-ship's commit. Commits the index with the message from stdin. On success
# the script prints nothing, so the output of a command chained with `&&`
# starts on the first line. A hook can print repo-controlled text, for example
# a file name that looks like a key. For this reason, the script captures the
# commit output and prints it only on failure: `commit_log<<<`, then that
# output without control bytes, to the end.

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
