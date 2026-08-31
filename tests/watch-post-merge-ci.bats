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
  # Fixed and short regardless of the argument: even with the grace now
  # clamped to the window (see the "startup grace" tests below, which swap in
  # a different stub to check the actual value requested), the default here
  # just needs to be fast for every other case.
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

@test "a non-hex merge sha exits 2" {
  run_script "not-a-sha!" 30
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

# A run gated on `if:` commonly concludes `neutral` or `skipped` on a merge
# that just doesn't trigger it - that is routine, not a red build, the same
# reading await-auto-merge.sh already gives NEUTRAL and SKIPPED check runs.
@test "a run that concluded neutral or skipped is not read as red" {
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"neutral","html_url":"https://x/1"},{"id":2,"status":"completed","conclusion":"skipped","html_url":"https://x/2"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=green"* ]]
}

# The same allowlist has to hold at the job level, not just the run level, or
# a run mixing a real failure with an unrelated skipped job would name the
# skipped one alongside the failing one.
@test "a job that concluded neutral or skipped is never named among the failing ones" {
  gh_runs_static \
    '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"failure","html_url":"https://x/1"}]}' \
    '{"jobs":[{"name":"deploy-only-on-release","conclusion":"skipped"},{"name":"lint-warnings","conclusion":"neutral"},{"name":"real failure","conclusion":"failure"}]}'
  run_script deadbee 30
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=red"* ]]
  [ "${lines[${#lines[@]}-1]}" = "$(printf 'https://x/1\treal failure')" ]
  [[ "$output" != *"deploy-only-on-release"* ]]
  [[ "$output" != *"lint-warnings"* ]]
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

# ─── the startup grace ─────────────────────────────────────────────────────

# record_sleep: replaces the suite's default no-op `sleep` stub with one that
# logs every requested duration instead of actually sleeping, so a test can
# tell the (now window-clamped) grace call apart from the poll cadence's own
# sleeps that follow it. The default stub in setup() ignores its argument
# entirely, which is exactly what would hide a regression here.
record_sleep() {
  cat > "$STUB_BIN/sleep" <<'SLEEPEOF'
#!/bin/sh
printf '%s\n' "$1" >> "$BATS_TEST_TMPDIR/sleep.log"
SLEEPEOF
  chmod +x "$STUB_BIN/sleep"
}

# Before this test existed, an unconditional `sleep 60` consumed the entire
# window before the poll loop's own `SECONDS -lt end` check ever ran, so a
# window at or under 60s always reported `verdict=timeout` with zero `gh`
# calls made - even when a run would have answered on the very first poll.
# The suite's default sleep stub (0.02s regardless of argument) could not
# catch that: it hid the real 60s cost, so every existing case here kept
# passing throughout. record_sleep exists specifically to close that gap.
@test "the startup grace is clamped when the window is at or under 60s, so a poll is still attempted" {
  record_sleep
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"}]}'
  run_script deadbee 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=green"* ]]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/sleep.log")" = "1" ]
}

@test "the startup grace stays at 60s for a window above 60s, matching the documented call sites" {
  record_sleep
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"completed","conclusion":"success","html_url":"https://x/1"}]}'
  run_script deadbee 570
  [ "$status" -eq 0 ]
  [ "$(sed -n 1p "$BATS_TEST_TMPDIR/sleep.log")" = "60" ]
}

# ─── the cap ───────────────────────────────────────────────────────────────

@test "cap: a run still incomplete after the window elapses" {
  gh_runs_static '{"workflow_runs":[{"id":1,"status":"in_progress","conclusion":null,"html_url":"https://x/1"}]}'
  run_script deadbee 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=timeout"* ]]
  [[ "$output" == *"https://x/1"* ]]
  [[ "$output" == *"gh-unreachable=no"* ]]
}

# Before gh-unreachable existed, this looked identical to the case above:
# verdict=timeout with an empty runs<<< block is exactly what "nothing has
# appeared yet" also prints. gh-unreachable is what tells them apart.
@test "cap: gh-unreachable is yes when no poll this call ever got a successful answer" {
  stub gh 'exit 1'
  run_script deadbee 2
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=timeout"* ]]
  [[ "$output" == *"gh-unreachable=yes"* ]]
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
