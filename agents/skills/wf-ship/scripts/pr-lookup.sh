#!/usr/bin/env bash
set -euo pipefail

# wf-ship's pull request lookup for the current branch. Output, by position:
#   on a hit:          pr_url=, pr_draft=yes|no, `pr_first_line<<<`, then the
#                      body's first line;
#   on any failure:    pr=none, `gh_log<<<`, then gh's stderr to the end.
# The first line and gh's stderr are remote text, so both lose bytes 0x00-0x08,
# 0x0B-0x1F and 0x7F. Matching `^Issue:` needs none of them.

usage() {
  cat <<'EOF'
Usage: pr-lookup.sh

Takes no arguments. Looks up the pull request for the current branch and
prints pr_url= and pr_draft= then the body's first line under
`pr_first_line<<<`, or pr=none then gh's error output under `gh_log<<<`.

Exit status:
  0  output is complete; route on the printed values
  2  usage error
EOF
}

if [ "$#" -ne 0 ]; then
  usage >&2
  exit 2
fi

strip_controls() { LC_ALL=C tr -d '\000-\010\013-\037\177'; }

lookup() {
  set -e
  local out url rest draft first
  # `line=` keeps an empty first line from being stripped with the trailing
  # newlines of the command substitution.
  out=$(gh pr view --json url,body,isDraft \
    --jq '.url, .isDraft, "line=" + (.body // "" | split("\n")[0])')
  url=${out%%$'\n'*}
  rest=${out#*$'\n'}
  draft=${rest%%$'\n'*}
  first=${rest#*$'\n'}
  case $draft in
    true) draft=yes ;;
    false) draft=no ;;
    *) echo "pr-lookup: unexpected isDraft value: $draft" >&2; return 1 ;;
  esac
  case $first in
    line=*) first=${first#line=} ;;
    *) echo 'pr-lookup: no body line in the gh output' >&2; return 1 ;;
  esac
  printf 'pr_url=%s\npr_draft=%s\npr_first_line<<<\n%s\n' "$url" "$draft" "$first" \
    | strip_controls
}

# gh's stderr is held, and printed under gh_log<<< only when the lookup fails.
# `set +e` around the capture, never `|| st=$?`: bash 5 ignores `set -e` inside
# a function called from a `||` list, command substitution included.
exec 3>&1
set +e
err=$(lookup 2>&1 >&3 3>&-)
st=$?
set -e
exec 3>&-
if [ "$st" -ne 0 ]; then
  printf 'pr=none\ngh_log<<<\n'
  [ -z "$err" ] || printf '%s\n' "$err" | strip_controls
fi
