#!/usr/bin/env bash
#
# wf-wrap Step 6's wait: give a post-merge CI run 60 seconds to appear, then
# poll for it every 15s for the first two minutes of polling, then every 60s,
# until every run for the merge commit is completed or the window given on
# the command line elapses.
#
# Usage: watch-post-merge-ci.sh <merge-sha> <window-seconds>
#
# Reaching the skill's promised 15-minute cap takes two calls, the same split
# as await-auto-merge.sh: window=570 first, then window=330 if the first
# prints `verdict=timeout`. The 60s grace runs again on that second call -
# simpler than threading a "skip grace" flag through a two-argument
# interface, and by the rare point a second call is needed a run has almost
# always already appeared. The repeat grace is drawn from that call's own
# budget rather than added on top - window is the call's whole clock, grace
# included, same as it always was - so 570+330 still totals 900s (15m); the
# second call just spends less of it polling. The two-minute
# fifteen-then-sixty-second cadence is timed from when polling starts within
# a call, not from when that call's grace starts.
#
# Exit status is always 0; the caller reads the terminal `verdict=` line
# rather than the exit status. Every poll still prints the raw `gh api`
# output first, so the skill's report can show progress.

set -uo pipefail

# Not `set -e`, for the same reason as await-auto-merge.sh: a `gh` failure
# mid-poll must fall through and retry, not abort the wait.

# poll_sleep, shared with await-auto-merge.sh so the family's cadence is tuned
# in one place.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/poll-cadence.sh"

usage() {
  echo "Usage: watch-post-merge-ci.sh <merge-sha> <window-seconds>"
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 2
fi

sha="$1"
window="$2"

if [ -z "$sha" ]; then
  echo "watch-post-merge-ci: merge-sha must not be empty" >&2
  exit 2
fi

case "$window" in
  ''|*[!0-9]*)
    echo "watch-post-merge-ci: window must be a non-negative integer, not '$window'" >&2
    exit 2
    ;;
esac

end=$((SECONDS + window))
sleep 60
start=$SECONDS
broke=0
out=""
while [ "$SECONDS" -lt "$end" ]; do
  # Key on head_sha, never on the branch: post-merge the branch is the
  # default branch, and a branch query would return every run on it,
  # including other people's. ~/.agents/AGENTS.md also rules out the
  # PR-checks subcommand, which 403s on a fine-grained PAT.
  out=$(gh api "repos/:owner/:repo/actions/runs?head_sha=$sha" --jq '.workflow_runs[] | "\(.id)\t\(.status)\t\(.conclusion // "-")\t\(.html_url)"')
  gh_status=$?
  printf '%s\n---\n' "$out"
  # A non-zero gh_status means the call itself failed - a transient network or
  # API error, not an empty result - so the wait keeps polling instead of
  # reading it as "no run appeared"; only a *successful* call that comes back
  # empty means that.
  if [ "$gh_status" -eq 0 ] && { [ -z "$out" ] || [ -z "$(cut -f2 <<<"$out" | grep -v '^completed$')" ]; }; then
    broke=1
    break
  fi
  poll_sleep "$start" "$end"
done

# The loop can end two ways: a break (some terminal state was read) or the
# window running out with every run still short of "completed". Only the
# break path has a `broke=1`, so it is what tells cap apart from the rest.
if [ "$broke" -ne 1 ]; then
  echo "elapsed=$SECONDS"
  echo "verdict=timeout"
  echo 'runs<<<'
  printf '%s\n' "$out"
  exit 0
fi

if [ -z "$out" ]; then
  echo "elapsed=$SECONDS"
  echo "verdict=absent"
  exit 0
fi

bad=$(printf '%s\n' "$out" | awk -F'\t' '$3 != "success" { print }')

if [ -z "$bad" ]; then
  echo "elapsed=$SECONDS"
  echo "verdict=green"
  exit 0
fi

echo "elapsed=$SECONDS"
echo "verdict=red"
echo 'jobs<<<'
printf '%s\n' "$bad" | while IFS=$'\t' read -r id run_status run_conclusion url; do
  [ -n "$id" ] || continue
  gh api "repos/:owner/:repo/actions/runs/${id}/jobs" --jq '.jobs[] | select(.conclusion != "success") | .name' 2>/dev/null \
    | while IFS= read -r name; do
        [ -n "$name" ] || continue
        printf '%s\t%s\n' "$url" "$name"
      done
done
