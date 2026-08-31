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
