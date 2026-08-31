#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SCRIPT="$DOTFILES_ROOT/agents/skills/wf-wrap/scripts/watch-post-merge-ci.sh"

# Real gh is never on PATH here; the stub below always answers, so a script
# bug that shells out somewhere unstubbed fails loudly rather than escaping to
# the real network.
setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_BIN"
  # Fixed and short regardless of the argument: the script's own 60s grace is
  # not scaled by the window the way its poll interval is, so a tiny window
  # alone would not keep this suite fast - the grace has to be stubbed too.
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

# gh_runs_static <runs-json> [jobs-json]: a gh stub that answers every
# `actions/runs?head_sha=` call with <runs-json> and every `.../jobs` call
# with [jobs-json] (default: none), each run through the real --jq filter the
# script passes. Both payloads are spliced into an unquoted heredoc, so they
# may hold double quotes (as JSON does) but not single ones.
gh_runs_static() {
  local jobs="$2"
  if [ -z "$jobs" ]; then jobs='{"jobs":[]}'; fi
  cat > "$STUB_BIN/gh" <<GHEOF
#!/bin/sh
path="\$2"
shift 2
jqf=""
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) jqf="\$2"; shift 2 ;;
    *) shift ;;
  esac
done
case "\$path" in
  *"/jobs") printf '%s' '$jobs' | jq -r "\$jqf" ;;
  *) printf '%s' '$1' | jq -r "\$jqf" ;;
esac
GHEOF
  chmod +x "$STUB_BIN/gh"
}

# gh_runs_sequence <first> <second> <third>: answers the runs query with
# <first> on the first poll, <second> on the second, and <third> from the
# third poll on - via a call counter file next to the stub. Used for the
# staggered-completions case; no test needs the jobs endpoint here.
gh_runs_sequence() {
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
if [ "\$n" -le 1 ]; then
  runs='$1'
elif [ "\$n" -le 2 ]; then
  runs='$2'
else
  runs='$3'
fi
printf '%s' "\$runs" | jq -r "\$jqf"
GHEOF
  chmod +x "$STUB_BIN/gh"
}

# gh_runs_flaky <n> <runs-json>: the first <n> calls exit non-zero with no
# output - gh itself failing, not an empty-but-successful answer - then every
# call after that answers <runs-json> the way gh_runs_static does. No test
# using this needs the jobs endpoint.
gh_runs_flaky() {
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

# ─── usage ──────────────────────────────────────────────────────────────

@test "no arguments exits 2" {
  run_script
  [ "$status" -eq 2 ]
}

@test "one argument exits 2" {
  run_script deadbee
  [ "$status" -eq 2 ]
}

@test "an empty merge sha exits 2" {
  run_script "" 30
  [ "$status" -eq 2 ]
}

@test "a non-numeric window exits 2" {
  run_script deadbee abc
  [ "$status" -eq 2 ]
}

# ─── the four documented outcomes ─────────────────────────────────────────

@test "no run appeared: verdict is absent" {
  gh_runs_static '{"workflow_runs":[]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=absent"* ]]
}

@test "a queued run: still polling, not read as absent or as completed" {
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"queued","conclusion":null,"html_url":"https://x/1"}]}'
  run_script deadbee 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=timeout"* ]]
  [[ "$output" == *"queued"* ]]
}

@test "staggered completions: polls through non-terminal statuses to green" {
  gh_runs_sequence \
    '{"workflow_runs":[{"id":1,"status":"in_progress","conclusion":null,"html_url":"https://x/1"},{"id":2,"status":"queued","conclusion":null,"html_url":"https://x/2"}]}' \
    '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"},{"id":2,"status":"in_progress","conclusion":null,"html_url":"https://x/2"}]}' \
    '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"},{"id":2,"status":"completed","conclusion":"success","html_url":"https://x/2"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=green"* ]]
  # Proves more than one poll actually happened, not just a lucky first read.
  [[ "$output" == *"in_progress"* ]]
}

@test "all runs already completed and passed: verdict is green on the first poll" {
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"},{"id":2,"status":"completed","conclusion":"success","html_url":"https://x/2"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=green"* ]]
}

@test "a run concluded otherwise: verdict is red and names the failing job, not the passing one" {
  gh_runs_static \
    '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"failure","html_url":"https://x/1"}]}' \
    '{"jobs":[{"name":"build","conclusion":"success"},{"name":"test, flaky","conclusion":"failure"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=red"* ]]
  [ "${lines[${#lines[@]}-1]}" = "$(printf 'https://x/1\ttest, flaky')" ]
  [[ "$output" != *$'\tbuild'* ]]
}

# ─── a gh call failing outright ────────────────────────────────────────────

# watch-post-merge-ci.sh is deliberately not `set -e`, for the same reason as
# await-auto-merge.sh: a failed call must fall through and retry, never read
# as the successful-but-empty answer that means "no run appeared". Only the
# later, successful call's payload can produce this verdict, so reaching it
# proves the failed call was survived rather than misread as absent.
@test "a gh call that fails outright is not read as 'no run appeared' - the wait keeps polling" {
  gh_runs_flaky 1 '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=green"* ]]
}

# ─── the cap ───────────────────────────────────────────────────────────────

@test "cap: a run still incomplete after the window elapses" {
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"in_progress","conclusion":null,"html_url":"https://x/1"}]}'
  run_script deadbee 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=timeout"* ]]
  [[ "$output" == *"https://x/1"* ]]
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
