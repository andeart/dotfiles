#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SCRIPT="$DOTFILES_ROOT/agents/skills/wf-wrap/scripts/await-auto-merge.sh"

# Real gh is never on PATH here; the stub below always answers, so a script
# bug that shells out somewhere unstubbed fails loudly rather than escaping to
# the real network.
setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_BIN"
  # The script's own interval math already shrinks each sleep to fit inside
  # the window, so a fixed short stub keeps every case here under a second of
  # real wall clock without having to fake $SECONDS.
  stub sleep 'exec /bin/sleep 0.02'
}

# stub <name> <body>: drop an executable of that name into the stub dir. Body
# runs under /bin/sh, so keep it POSIX.
stub() {
  printf '#!/bin/sh\n%s\n' "$2" > "$STUB_BIN/$1"
  chmod +x "$STUB_BIN/$1"
}

run_script() {
  run env PATH="$STUB_BIN:$PATH" bash "$SCRIPT" "$@"
}

# after_marker <output>: the lines following the last `checks<<<` marker - the
# one the final verdict block emits, not the one inside the raw poll dump this
# script also prints, which carries the same list under the same marker.
after_marker() {
  local rest=${1##*checks<<<}
  printf '%s\n' "${rest#$'\n'}"
}

# gh_static <payload-json>: a gh stub that answers every `pr view` call with
# the same payload, run through the real --jq filter the script passes - so
# tests exercise the filter actually written into the script, not a copy of
# it. The payload is spliced into an unquoted heredoc, so it may contain
# double quotes (as JSON does) but not single ones.
gh_static() {
  cat > "$STUB_BIN/gh" <<GHEOF
#!/bin/sh
shift 2
jqf=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) jqf="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
printf '%s' '$1' | jq -r "\$jqf"
GHEOF
  chmod +x "$STUB_BIN/gh"
}

# gh_sequence <n> <first-payload> <second-payload>: answers the first <n>
# polls with the first payload and every poll after that with the second, via
# a call counter file next to the stub (self-contained: baked-in path, not
# $0-derived, since a PATH-resolved argv[0] is not guaranteed to be absolute).
gh_sequence() {
  cat > "$STUB_BIN/gh" <<GHEOF
#!/bin/sh
shift 2
jqf=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) jqf="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
countfile="$STUB_BIN/calls"
n=\$(( \$(wc -l < "\$countfile" 2>/dev/null || echo 0) + 1 ))
echo >> "\$countfile"
if [ "\$n" -le $1 ]; then
  payload='$2'
else
  payload='$3'
fi
printf '%s' "\$payload" | jq -r "\$jqf"
GHEOF
  chmod +x "$STUB_BIN/gh"
}

# gh_flaky <n> <payload>: the first <n> calls exit non-zero with no output -
# gh itself failing, not an empty-but-successful answer - then every call
# after that answers <payload> the way gh_static does.
gh_flaky() {
  cat > "$STUB_BIN/gh" <<GHEOF
#!/bin/sh
shift 2
jqf=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) jqf="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
countfile="$STUB_BIN/calls"
n=\$(( \$(wc -l < "\$countfile" 2>/dev/null || echo 0) + 1 ))
echo >> "\$countfile"
if [ "\$n" -le $1 ]; then
  exit 1
fi
printf '%s' '$2' | jq -r "\$jqf"
GHEOF
  chmod +x "$STUB_BIN/gh"
}

# rollup: one entry per value of GitHub's CheckConclusionState and
# StatusState, plus every non-terminal CheckStatusState, a name carrying a
# comma, and a conclusion GitHub has not defined yet. The member list is
# pinned beside the allowlist itself in await-auto-merge.sh - keep this
# fixture in step with it rather than letting the two drift apart.
rollup() {
  printf '%s' '{"state":"OPEN","mergeCommit":null,"headRefOid":"abc123","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"BLOCKED","statusCheckRollup":[{"name":"ok-success","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"ok-neutral","status":"COMPLETED","conclusion":"NEUTRAL"},{"name":"ok-skipped","status":"COMPLETED","conclusion":"SKIPPED"},{"name":"bad-failure","status":"COMPLETED","conclusion":"FAILURE"},{"name":"bad-timed-out","status":"COMPLETED","conclusion":"TIMED_OUT"},{"name":"bad-cancelled","status":"COMPLETED","conclusion":"CANCELLED"},{"name":"bad-action-required","status":"COMPLETED","conclusion":"ACTION_REQUIRED"},{"name":"bad-startup-failure","status":"COMPLETED","conclusion":"STARTUP_FAILURE"},{"name":"bad-stale","status":"COMPLETED","conclusion":"STALE"},{"name":"pending-queued","status":"QUEUED","conclusion":null},{"name":"pending-in-progress","status":"IN_PROGRESS","conclusion":null},{"name":"pending-waiting","status":"WAITING","conclusion":null},{"name":"pending-requested","status":"REQUESTED","conclusion":null},{"name":"pending-pending","status":"PENDING","conclusion":null},{"name":"bad, with a comma","status":"COMPLETED","conclusion":"FAILURE"},{"context":"ctx-success","state":"SUCCESS"},{"context":"ctx-expected","state":"EXPECTED"},{"context":"ctx-pending","state":"PENDING"},{"context":"ctx-error","state":"ERROR"},{"context":"ctx-failure","state":"FAILURE"},{"name":"future-conclusion","status":"COMPLETED","conclusion":"NOT_YET_INVENTED"}]}'
}

# ─── usage ──────────────────────────────────────────────────────────────

@test "no arguments exits 2" {
  run_script
  [ "$status" -eq 2 ]
}

@test "one argument exits 2" {
  run_script 123
  [ "$status" -eq 2 ]
}

@test "an empty pr number exits 2" {
  run_script "" 30
  [ "$status" -eq 2 ]
}

@test "a non-numeric pr number exits 2" {
  run_script abc 30
  [ "$status" -eq 2 ]
}

@test "a non-numeric window exits 2" {
  run_script 123 abc
  [ "$status" -eq 2 ]
}

@test "an empty window exits 2" {
  run_script 123 ""
  [ "$status" -eq 2 ]
}

# ─── the five documented stop conditions ─────────────────────────────────

@test "merged: verdict names the merge and carries the merge SHA and head OID" {
  gh_static '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=merged"* ]]
  [[ "$output" == *"merge-sha=deadbee"* ]]
  [[ "$output" == *"head-oid=f00"* ]]
}

# The order the loop tests conditions in is load-bearing: autoMergeRequest
# stays non-null on a PR that auto-merge actually landed, so this payload
# would read as "disarmed" if that check ran first.
@test "merged: autoMergeRequest survives the merge, which is why MERGED is read first" {
  gh_static '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  run_script 123 30
  [[ "$output" == *"verdict=merged"* ]]
  [[ "$output" != *"verdict=disarmed"* ]]
}

@test "closed: verdict names the close" {
  gh_static '{"state":"CLOSED","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":null,"mergeStateStatus":"CLEAN","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=closed"* ]]
}

@test "disarmed: verdict names the disarm" {
  gh_static '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":null,"mergeStateStatus":"CLEAN","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=disarmed"* ]]
}

@test "dirty: verdict names the conflict" {
  gh_static '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"DIRTY","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=dirty"* ]]
}

@test "checks-failed: names every non-passing check, a comma in the name included" {
  gh_static '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"ok","status":"COMPLETED","conclusion":"SUCCESS"},{"name":"bad, with a comma","status":"COMPLETED","conclusion":"FAILURE"}]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=checks-failed"* ]]
  # The passing check is never in the jq filter's own output at all - it is
  # an allowlist - so the last line is the final verdict block's one name.
  [ "${lines[${#lines[@]}-1]}" = "bad, with a comma" ]
}

# ─── checks: the allowlist against every enum member ─────────────────────

@test "checks: every conclusion that is not a pass is reported, in order" {
  gh_static "$(rollup)"
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=checks-failed"* ]]
  run after_marker "$output"
  [ "${lines[0]}" = "bad-failure" ]
  [ "${lines[1]}" = "bad-timed-out" ]
  [ "${lines[2]}" = "bad-cancelled" ]
  [ "${lines[3]}" = "bad-action-required" ]
  [ "${lines[4]}" = "bad-startup-failure" ]
  [ "${lines[5]}" = "bad-stale" ]
  [ "${lines[6]}" = "bad, with a comma" ]
  [ "${lines[7]}" = "ctx-error" ]
  [ "${lines[8]}" = "ctx-failure" ]
  [ "${lines[9]}" = "future-conclusion" ]
  [ "${#lines[@]}" -eq 10 ]
}

@test "checks: passing conclusions and states are never reported" {
  gh_static "$(rollup)"
  run_script 123 30
  [[ "$output" != *"ok-success"* ]]
  [[ "$output" != *"ok-neutral"* ]]
  [[ "$output" != *"ok-skipped"* ]]
  [[ "$output" != *"ctx-success"* ]]
  [[ "$output" != *"ctx-expected"* ]]
}

@test "checks: a check still running is pending, not a failure" {
  gh_static "$(rollup)"
  run_script 123 30
  [[ "$output" != *"pending-queued"* ]]
  [[ "$output" != *"pending-in-progress"* ]]
  [[ "$output" != *"pending-waiting"* ]]
  [[ "$output" != *"pending-requested"* ]]
  [[ "$output" != *"pending-pending"* ]]
  [[ "$output" != *"ctx-pending"* ]]
}

@test "checks: a conclusion GitHub has not defined yet reads as a failure, not a pass" {
  gh_static '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"CLEAN","statusCheckRollup":[{"name":"brand-new","status":"COMPLETED","conclusion":"NOT_YET_INVENTED"}]}'
  run_script 123 30
  [[ "$output" == *"verdict=checks-failed"* ]]
  [[ "$output" == *"brand-new"* ]]
}

# ─── still pending: the wait keeps polling rather than stopping early ────

@test "pending: keeps polling until a later poll reports a stop condition" {
  gh_sequence 1 \
    '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}' \
    '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=merged"* ]]
  # Proves more than one poll actually happened, not just a lucky first read.
  [[ "$output" == *"OPEN"* ]]
}

# ─── a gh call failing outright ────────────────────────────────────────────

# await-auto-merge.sh is deliberately not `set -e`: a `gh` failure mid-poll
# must fall through to the interval arithmetic and loop again, not be read as
# any stop condition. gh_status gates the stop-condition checks explicitly, so
# a failed call's output is never parsed at all rather than merely failing to
# match MERGED/disarmed/DIRTY/checks-failed by accident. Only the later,
# successful call's payload can produce this verdict, so reaching it proves
# the failed call was survived.
@test "a gh call that fails outright is not read as a stop condition - the wait keeps polling" {
  gh_flaky 1 \
    '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  run_script 123 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=merged"* ]]
}

# ─── the cap ───────────────────────────────────────────────────────────────

@test "cap: names the last known merge state once the window elapses" {
  gh_static '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  run_script 123 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=cap"* ]]
  [[ "$output" == *"merge-state-status=UNKNOWN"* ]]
}

# ─── bash 3.2 compatibility ────────────────────────────────────────────────

# The script's shebang resolves to bash 5.x on this machine's PATH, so a
# passing `bash -n` proves nothing about macOS's shipped /bin/bash 3.2 - only
# running the parser under 3.2 itself does. CI runs Ubuntu, where /bin/bash is
# already 5.x, so skip there rather than pass trivially.
@test "the script parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$SCRIPT"
  [ "$status" -eq 0 ]
}
