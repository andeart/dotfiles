#!/usr/bin/env bash
set -euo pipefail

# wf-wrap's Step 1c: whether <feature>'s content is already on <default-ref>,
# whichever merge method landed it. Prints `head=`, one `landed=` line per probe
# that answers, then `probed=yes`.
#
# One probe per merge method, and any one answering is the whole proof:
#   ancestor  the tip is reachable from the default branch (merge commit)
#   squash    the branch's tree squashed onto its merge base is a patch already
#             upstream (squash merge)
#   replayed  mb..<feature> holds at least one commit, and every one has an
#             equivalent patch upstream (rebase merge)
# Each probe is the only one answering for its method, so none is redundant.
# tests/wf-wrap-landing-probe.bats pins a row per method and the cases that have
# to stay silent.
#
# Do not substitute `git diff <feature> <default-ref>` for the probes. It looks
# equivalent, but reports a difference as soon as any unrelated commit lands on
# the default branch.

wf_usage() {
  cat <<'EOF'
Usage: landing-probe.sh <default-ref> <feature>

Probes whether <feature>'s content has landed on <default-ref>, writing
`key=value` lines to stdout and ending with `probed=yes`.

Exit status:
  0  reached its output; no `landed=` line means nothing landed
  2  usage error, including an argument beginning with `-`
EOF
}

if [ "$#" -ne 2 ]; then
  wf_usage >&2
  exit 2
fi

# git reads a ref beginning with `-` as an option. Checked on the first
# character only, never on whether the ref resolves: an unresolvable ref still
# has to reach `probed=yes`.
for ref in "$1" "$2"; do
  case "$ref" in
    -*) wf_usage >&2; exit 2 ;;
  esac
done
default_ref=$1
feature=$2

# The `|| mb=` and `|| true` guards keep set -e from stopping the script short of
# `probed=yes`, which would turn "nothing landed" into silence.
mb=$(git merge-base "$default_ref" "$feature") || mb=
echo "head=$(git rev-parse "$feature")"
git merge-base --is-ancestor "$feature" "$default_ref" && echo 'landed=ancestor'
# The probe commit is dangling and gets garbage-collected; no ref moves.
git cherry "$default_ref" "$(git commit-tree "$(git rev-parse "$feature^{tree}")" -p "$mb" -m squash-probe)" \
  | awk '$1 == "-" { print "landed=squash" }' || true
# `NR &&`: a cherry that failed prints nothing, which must not read as every
# commit being upstream, since `landed=` authorises wf-wrap's discard.
git cherry "$default_ref" "$feature" \
  | awk '$1 == "+" { n++ } END { if (NR && !n) print "landed=replayed" }' || true
echo 'probed=yes'
