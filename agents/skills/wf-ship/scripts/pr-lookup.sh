#!/usr/bin/env bash
set -euo pipefail

# wf-ship's pull request lookup for the current branch. Output, by position:
#   on a hit:      pr_url=, pr_draft=yes|no, `pr_first_line<<<`, then the first
#                  line of the body;
#   on a failure:  pr=none, `gh_log<<<`, then the stderr of gh to the end.
# The first line and the stderr of gh are remote text. The script removes bytes
# 0x00-0x08, 0x0B-0x1F and 0x7F from both. The `^Issue:` match needs none of
# these bytes.

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
  # The `line=` prefix keeps an empty first line. Without the prefix, the
  # command substitution removes that line with the trailing newlines.
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

# The script holds the stderr of gh and prints it under gh_log<<< only when the
# lookup fails. Use `set +e` around the capture, not `|| st=$?`: bash 5 ignores
# `set -e` in a function that runs as part of a `||` list, also in a command
# substitution.
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
