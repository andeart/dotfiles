#!/usr/bin/env bash
set -euo pipefail

# wf-ship's working-notes search. Finds the untracked and ignored files in the
# current repository whose path names <ID>, and prints one keyed line per match:
#   target=<path>      absolute path, single-quoted for a shell, each `'` as '\''
#   unquotable=<line>  a path that git printed C-quoted, exactly as git printed
#                      it. That text is not the file name, so it is never a
#                      target.
#   nested=<path>      absolute path, not quoted, of a directory that holds its
#                      own repository, a worktree included. git lists it as one
#                      `dir/` line. Deleting it deletes that whole checkout.
# wf-ship puts the `target=` values into an `rm -rf` that the user runs, so the
# quoting is here, where a test can reach it.

wf_usage() {
  cat <<'EOF'
Usage: find-working-notes.sh <ID>

Lists the untracked and ignored files in the current repository whose path
names the work item identifier <ID> (letters, a hyphen, digits), as `target=`,
`unquotable=` and `nested=` lines on stdout.

Exit status:
  0  output is complete; no lines means no notes
  2  usage error, including an <ID> of any other shape
EOF
}

# The identifier goes into a pathspec and an ERE, so it must have this shape.
id_shape='^[A-Za-z]+-[0-9]+$'
if [ "$#" -ne 1 ] || ! [[ $1 =~ $id_shape ]]; then
  wf_usage >&2
  exit 2
fi
id=$1
root=$(git rev-parse --show-toplevel)

# No --exclude-standard, so ignored paths are listed with untracked ones.
# ls-files lists each file in an untracked or ignored directory, not the
# directory. core.quotePath=false prints a non-ASCII name unquoted; git still
# C-quotes a path that holds `"`, `\` or a control character.
#
# Never -z: with each NUL changed to a newline, a name that holds a newline
# becomes several lines, and one of them can read `../...`.
#
# The pathspec stops ls-files from printing every ignored path, such as
# node_modules/. Its `*` matches across `/` and icase agrees with grep -i, so it
# passes a superset of the grep match below. The grep match decides.
listing=$(git -c core.quotePath=false ls-files -o --full-name -- ":(top,icase)*${id}*")

# Bounded on both sides, because a false match is a file that the user deletes.
# The left bound keeps DX-98 out of idx-98; the right bound keeps DX-5 out of
# dx-57. Do not change either bound to a substring match. grep exit 1 means no
# match, which is a valid answer. LC_ALL=C because the listing is raw bytes: in
# a UTF-8 locale, grep skips a line that holds an invalid sequence.
matches=$(printf '%s\n' "$listing" | LC_ALL=C grep -iE -e "(^|[^A-Za-z])${id}([^0-9]|$)") || [ "$?" -eq 1 ]

# One awk pass, not one process per match: a matched directory gives one line
# per file in it. ROOT goes through ENVIRON because -v processes backslash
# escapes. shell_quote uses index(), so no backslash goes through the
# replacement rules of gsub.
printf '%s\n' "$matches" | ROOT="$root" awk -v q="'" '
  function shell_quote(s,   out, i) {
    out = ""
    while ((i = index(s, q)) > 0) {
      out = out substr(s, 1, i - 1) q "\\" q q
      s = substr(s, i + 1)
    }
    return q out s q
  }
  $0 == "" { next }
  /^"/ { print "unquotable=" $0; next }
  /\/$/ { print "nested=" ENVIRON["ROOT"] "/" $0; next }
  { print "target=" shell_quote(ENVIRON["ROOT"] "/" $0) }'
