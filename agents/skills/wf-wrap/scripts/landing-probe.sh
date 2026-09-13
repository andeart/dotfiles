#!/usr/bin/env bash
set -euo pipefail

# wf-wrap's Step 1c. Tells whether the content of <feature> is already on
# <default-ref>, for any merge method. Prints `head=`, one `landed=` line for
# each probe that answers, then `probed=yes`.
#
# One probe per merge method, and one answer is the full proof:
#   ancestor  the tip is an ancestor of the default branch (merge commit)
#   squash    the branch tree, as one commit on the merge base, is a patch
#             that is already upstream (squash merge)
#   replayed  mb..<feature> holds at least one commit, and each one has an
#             equal patch upstream (rebase merge)
# Each probe is the only one that answers for its method, so do not remove one.
# tests/wf-wrap-landing-probe.bats has one case per method and the cases that
# must stay silent.
#
# Do not use `git diff <feature> <default-ref>` instead of the probes. It shows a
# difference when any unrelated commit lands on the default branch.

wf_usage() {
  cat <<'EOF'
Usage: landing-probe.sh <default-ref> <feature>

Tells whether the content of <feature> has landed on <default-ref>. Both
arguments are full refnames, such as refs/remotes/origin/main and
refs/heads/<branch>. Writes `key=value` lines to stdout, ending with
`probed=yes`.

Exit status:
  0  output is complete; no `landed=` line means nothing landed
  2  usage error, including an argument that does not start with `refs/`
EOF
}

if [ "$#" -ne 2 ]; then
  wf_usage >&2
  exit 2
fi

# Full refnames only: git resolves a short name to a same-named tag before the
# branch, and a fetch brings in the tags of the remote. An argument that starts
# with `refs/` also cannot be read as an option. Check only the prefix, not
# whether the ref resolves: an unresolvable ref must still reach `probed=yes`.
for ref in "$1" "$2"; do
  case "$ref" in
    refs/*) ;;
    *) wf_usage >&2; exit 2 ;;
  esac
done
default_ref=$1
feature=$2

# An unresolvable ref is a "nothing landed" answer, not a script failure. The
# `|| mb=` and `|| true` guards stop set -e from ending the script before
# `probed=yes`.
mb=$(git merge-base "$default_ref" "$feature") || mb=
echo "head=$(git rev-parse "$feature")"
git merge-base --is-ancestor "$feature" "$default_ref" && echo 'landed=ancestor'
# The squash probe commit is dangling, and git garbage-collects it. No ref moves.
git cherry "$default_ref" "$(git commit-tree "$(git rev-parse "$feature^{tree}")" -p "$mb" -m squash-probe)" \
  | awk '$1 == "-" { print "landed=squash" }' || true
# `NR &&`: a failed git cherry prints no lines. Without the guard, no lines reads
# as "each commit is upstream", and `landed=` authorises wf-wrap's discard.
git cherry "$default_ref" "$feature" \
  | awk '$1 == "+" { n++ } END { if (NR && !n) print "landed=replayed" }' || true
echo 'probed=yes'
