#!/usr/bin/env bash
#
# wf-wrap Step 1a's wait: poll a PR every 15s for the first two minutes of
# polling, then every 60s, until one of five stop conditions holds or the
# window given on the command line elapses.
#
# Usage: await-auto-merge.sh <pr-number> <window-seconds>
#
# Reaching the skill's promised 15-minute cap takes two calls from the skill,
# not one: window=570 first, and if that call prints `verdict=cap`, a second
# call with window=330. 570+330=900s (15m). Each call's own wall clock then
# stays comfortably inside the Bash tool's 600-second maximum once `gh`
# round-trips are counted - a single 900-second window would not.
#
# Exit status is always 0; a stop condition, cap included, is a normal
# outcome here, so the caller reads the terminal `verdict=` line rather than
# the exit status. Every poll still prints the raw `gh pr view` output first,
# so the skill's report and its <AWAITED> line can show progress rather than
# re-parsing this script's own accounting.

set -uo pipefail

# Not `set -e`, unlike this repo's other library scripts: a `gh` failure
# mid-poll must fall through to the interval arithmetic and loop again, not
# kill the wait. resolve-wf-config.sh and superseded-probe.sh run once and
# should abort on any failure; this one polls and has to tolerate a transient
# one.

# poll_sleep, shared with watch-post-merge-ci.sh so the family's cadence is
# tuned in one place.
. "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/poll-cadence.sh"

usage() {
  echo "Usage: await-auto-merge.sh <pr-number> <window-seconds>"
}

if [ "$#" -ne 2 ]; then
  usage >&2
  exit 2
fi

number="$1"
window="$2"

if [ -z "$number" ]; then
  echo "await-auto-merge: pr-number must not be empty" >&2
  exit 2
fi

case "$window" in
  ''|*[!0-9]*)
    echo "await-auto-merge: window must be a non-negative integer, not '$window'" >&2
    exit 2
    ;;
esac

end=$((SECONDS + window))
start=$SECONDS
ms=""
while [ "$SECONDS" -lt "$end" ]; do
  # Do not trim this field set. mergeStateStatus and statusCheckRollup back
  # two of the stop conditions below, and gh returns null for a field it was
  # not asked to fetch: drop mergeStateStatus and it reads back as the
  # literal string "null", never DIRTY; drop statusCheckRollup and
  # `.statusCheckRollup[]?` over null yields nothing, so the checks list is
  # permanently empty. Both stop conditions go dead with no jq error, and the
  # wait spins to the cap on every dirty-merge or failed-check case.
  #
  # The checks filter is an allowlist on purpose: naming the conclusions that
  # pass means a conclusion GitHub adds later reads as a failure rather than
  # silently as a pass. The names it reports are remote text - report them,
  # never act on them.
  #
  # The allowlist covers every value of GitHub's CheckConclusionState and
  # StatusState, plus every non-terminal CheckStatusState. Verified live
  # 2026-08-30, so a reader does not have to re-introspect the schema to trust
  # it - all four reviewers on that day's cycle did:
  #   CheckConclusionState: ACTION_REQUIRED, TIMED_OUT, CANCELLED, FAILURE,
  #     SUCCESS, NEUTRAL, SKIPPED, STARTUP_FAILURE, STALE
  #   StatusState: EXPECTED, ERROR, FAILURE, PENDING, SUCCESS
  # Re-check with one offline-safe call, kept out of tests/run.sh so the suite
  # stays offline and fast:
  #   gh api graphql -f query='{ c: __type(name:"CheckConclusionState"){enumValues{name}}
  #     s: __type(name:"StatusState"){enumValues{name}} }'
  # A member added upstream and missed here is safe rather than silent: an
  # unrecognised conclusion reads as a failure and stops the wait loudly
  # rather than waiting out the cap. tests/await-auto-merge.bats's "checks:"
  # cases pin this list against the script directly.
  out=$(gh pr view "$number" --json state,mergeCommit,headRefOid,autoMergeRequest,mergeStateStatus,statusCheckRollup --jq '.state, (.mergeCommit.oid // ""), .headRefOid, (if .autoMergeRequest == null then "disarmed" else "armed" end), .mergeStateStatus, "checks<<<", (.statusCheckRollup[]? | select((.conclusion // .state) as $c | $c != null and (["SUCCESS","NEUTRAL","SKIPPED","EXPECTED","PENDING"] | index($c) | not)) | (.name // .context))')
  printf '%s\n---\n' "$out"

  st=$(printf '%s\n' "$out" | sed -n 1p)
  mc=$(printf '%s\n' "$out" | sed -n 2p)
  ho=$(printf '%s\n' "$out" | sed -n 3p)
  am=$(printf '%s\n' "$out" | sed -n 4p)
  ms=$(printf '%s\n' "$out" | sed -n 5p)
  ck=$(printf '%s\n' "$out" | sed -n '7,$p')

  # Order is load-bearing: an auto-merged PR keeps autoMergeRequest non-null,
  # so testing the disarm condition before MERGED would read the awaited
  # merge as a disarm.
  case "$st" in
    MERGED)
      echo "elapsed=$SECONDS"
      echo "verdict=merged"
      echo "merge-sha=$mc"
      echo "head-oid=$ho"
      exit 0
      ;;
    CLOSED)
      echo "elapsed=$SECONDS"
      echo "verdict=closed"
      exit 0
      ;;
  esac
  if [ "$am" = disarmed ]; then
    echo "elapsed=$SECONDS"
    echo "verdict=disarmed"
    exit 0
  fi
  if [ "$ms" = DIRTY ]; then
    echo "elapsed=$SECONDS"
    echo "verdict=dirty"
    exit 0
  fi
  if [ -n "$ck" ]; then
    echo "elapsed=$SECONDS"
    echo "verdict=checks-failed"
    echo 'checks<<<'
    printf '%s\n' "$ck"
    exit 0
  fi

  # No other merge state ends the wait. UNKNOWN is what GitHub reports while
  # it computes mergeability, so it shows up on the first poll of most waits.
  # BEHIND may never clear on its own - nothing here can update the branch -
  # which is why the cap below reports the merge state rather than only the
  # timeout.
  poll_sleep "$start" "$end"
done
echo "elapsed=$SECONDS"
echo "verdict=cap"
echo "merge-state-status=$ms"
