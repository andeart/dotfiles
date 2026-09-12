#!/usr/bin/env bash
set -euo pipefail

# wf-ship's working-notes search: the untracked and ignored files in the current
# repository whose path names <ID>. Prints one keyed line per match:
#   target=<path>      absolute, single-quoted for a shell, each `'` as '\''
#   unquotable=<line>  a path git printed C-quoted, exactly as git printed it.
#                      That is git's escaped form rather than the file's name,
#                      so no quoting makes it a correct target.
# wf-ship pastes `target=` values into an `rm -rf` the user runs, which is why
# the quoting lives here, where a test reaches it.

wf_usage() {
  cat <<'EOF'
Usage: find-working-notes.sh <ID>

Lists the untracked and ignored files in the current repository whose path
names the work item identifier <ID> (letters, a hyphen, digits), as `target=`
and `unquotable=` lines on stdout.

Exit status:
  0  reached its output; no lines means no notes
  2  usage error, including an <ID> of any other shape
EOF
}

# The identifier becomes part of an ERE below, so nothing else reaches it.
id_shape='^[A-Za-z]+-[0-9]+$'
if [ "$#" -ne 1 ] || ! [[ $1 =~ $id_shape ]]; then
  wf_usage >&2
  exit 2
fi
id=$1
root=$(git rev-parse --show-toplevel)

# Leaving out --exclude-standard is what brings ignored paths in beside the
# untracked ones; a repo's .gitignore decides which of the two its notes land
# in. ls-files lists the files inside an untracked or ignored directory rather
# than the directory itself. core.quotePath=false prints a non-ASCII name as
# itself; git still C-quotes a path holding `"`, `\` or a control character.
#
# Never -z: split on NUL and re-joined on newlines, a name holding a newline
# becomes lines of its own, and one of them can read `../...`.
listing=$(git -c core.quotePath=false ls-files -o --full-name -- :/)

# Bounded on both sides, because a false match is a file the user deletes by
# hand. The left bound keeps DX-98 out of idx-98-...; the right keeps DX-5 out
# of dx-57, of which dx-5 is a literal prefix. Do not loosen either back to a
# substring match. Finding nothing is an answer, so grep's exit 1 is absorbed
# and only a real grep failure stops the script.
matches=$(printf '%s\n' "$listing" | grep -iE -e "(^|[^A-Za-z])${id}([^0-9]|$)") || [ "$?" -eq 1 ]

while IFS= read -r line; do
  [ -n "$line" ] || continue
  case "$line" in
    \"*) printf 'unquotable=%s\n' "$line" ;;
    *) printf "target='%s'\n" "$(printf '%s' "$root/$line" | sed "s/'/'\\\\''/g")" ;;
  esac
done <<< "$matches"
