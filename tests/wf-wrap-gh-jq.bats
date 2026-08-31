#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-wrap/SKILL.md"

# Both jq programs are read out of SKILL.md rather than copied here. The skill
# is the only place they exist - nothing executes that file - so a copy would
# grade a stale expression and pass while the real one rotted.

# The poll command lives inside a `while` loop in SKILL.md, so it is indented
# and assigned to a variable. This used to anchor at column zero, which matches
# nothing there and silently grades an empty program - hence the extraction
# case below, which fails by name instead. Two patterns are tried so the same
# extractor works on the bare, pre-loop shape and the indented, assigned one -
# only one of the two ever exists in the file at a time.
poll_jq() {
  sed -n \
    -e "s/^gh pr view <number> --json .*--jq '\(.*\)'\$/\1/p" \
    -e "s/^[[:space:]]*out=\$(gh pr view <number> --json [^ ]* --jq '\(.*\)')\$/\1/p" \
    "$SKILL"
}

lookup_jq() {
  sed -n "s/^gh pr view --json .*--jq '\(.*\)'\$/\1/p" "$SKILL"
}

# The --json field list beside each filter. gh returns only the fields it was
# asked for and jq answers null for the rest, so the two halves of one command
# can drift apart without either erroring.
poll_json() {
  sed -n \
    -e "s/^gh pr view <number> --json \([^ ]*\) --jq .*/\1/p" \
    -e "s/^[[:space:]]*out=\$(gh pr view <number> --json \([^ ]*\) --jq .*/\1/p" \
    "$SKILL"
}

lookup_json() {
  sed -n "s/^gh pr view --json \([^ ]*\) --jq .*/\1/p" "$SKILL"
}

# Step 6's run-watch filter. Same reasoning as poll_jq: it moves into a loop in
# SKILL.md, so it is indented and assigned, and an extractor anchored at column
# zero would grade nothing.
watch_jq() {
  sed -n "s/^[[:space:]]*out=\$(gh api \"repos\/:owner\/:repo\/actions\/runs?head_sha=<MERGE_SHA>\" --jq '\(.*\)')\$/\1/p" "$SKILL"
}

# narrow <json> <field list>: the payload gh would actually hand back for that
# --json list - only those top-level keys.
narrow() {
  jq -c --arg keys "$2" 'with_entries(select(.key as $k | ($keys | split(",")) | index($k)))' <<<"$1"
}

# after_marker <output>: the lines following the checks<<< marker.
after_marker() {
  local rest=${1#*checks<<<}
  printf '%s\n' "${rest#$'\n'}"
}

# run_poll <json>: the poll's jq program applied to one payload.
run_poll() {
  run jq -r "$(poll_jq)" <<<"$1"
  [ "$status" -eq 0 ]
}

run_lookup() {
  run jq -r "$(lookup_jq)" <<<"$1"
  [ "$status" -eq 0 ]
}

# One entry per value of GitHub's CheckConclusionState and StatusState, plus
# every non-terminal CheckStatusState, a name carrying a comma, and a
# conclusion GitHub has not defined yet.
#
# Verified live 2026-08-30, so a reader does not have to re-introspect the
# schema to trust the list:
#   CheckConclusionState: ACTION_REQUIRED, TIMED_OUT, CANCELLED, FAILURE,
#     SUCCESS, NEUTRAL, SKIPPED, STARTUP_FAILURE, STALE
#   StatusState: EXPECTED, ERROR, FAILURE, PENDING, SUCCESS
#
# Re-check with one offline-safe call, kept out of the suite so `tests/run.sh`
# stays offline and fast:
#   gh api graphql -f query='{ c: __type(name:"CheckConclusionState"){enumValues{name}}
#     s: __type(name:"StatusState"){enumValues{name}} }'
#
# A member added upstream and missed here is safe rather than silent: the poll's
# allowlist reads an unrecognised conclusion as a failure and stops loudly.
rollup() {
  cat <<'JSON'
{"state":"OPEN","mergeCommit":null,"headRefOid":"abc123","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"BLOCKED","statusCheckRollup":[
 {"__typename":"CheckRun","name":"ok-success","status":"COMPLETED","conclusion":"SUCCESS"},
 {"__typename":"CheckRun","name":"ok-neutral","status":"COMPLETED","conclusion":"NEUTRAL"},
 {"__typename":"CheckRun","name":"ok-skipped","status":"COMPLETED","conclusion":"SKIPPED"},
 {"__typename":"CheckRun","name":"bad-failure","status":"COMPLETED","conclusion":"FAILURE"},
 {"__typename":"CheckRun","name":"bad-timed-out","status":"COMPLETED","conclusion":"TIMED_OUT"},
 {"__typename":"CheckRun","name":"bad-cancelled","status":"COMPLETED","conclusion":"CANCELLED"},
 {"__typename":"CheckRun","name":"bad-action-required","status":"COMPLETED","conclusion":"ACTION_REQUIRED"},
 {"__typename":"CheckRun","name":"bad-startup-failure","status":"COMPLETED","conclusion":"STARTUP_FAILURE"},
 {"__typename":"CheckRun","name":"bad-stale","status":"COMPLETED","conclusion":"STALE"},
 {"__typename":"CheckRun","name":"pending-queued","status":"QUEUED","conclusion":null},
 {"__typename":"CheckRun","name":"pending-in-progress","status":"IN_PROGRESS","conclusion":null},
 {"__typename":"CheckRun","name":"pending-waiting","status":"WAITING","conclusion":null},
 {"__typename":"CheckRun","name":"pending-requested","status":"REQUESTED","conclusion":null},
 {"__typename":"CheckRun","name":"pending-pending","status":"PENDING","conclusion":null},
 {"__typename":"CheckRun","name":"bad, with a comma","status":"COMPLETED","conclusion":"FAILURE"},
 {"__typename":"StatusContext","context":"ctx-success","state":"SUCCESS"},
 {"__typename":"StatusContext","context":"ctx-expected","state":"EXPECTED"},
 {"__typename":"StatusContext","context":"ctx-pending","state":"PENDING"},
 {"__typename":"StatusContext","context":"ctx-error","state":"ERROR"},
 {"__typename":"StatusContext","context":"ctx-failure","state":"FAILURE"},
 {"__typename":"CheckRun","name":"future-conclusion","status":"COMPLETED","conclusion":"NOT_YET_INVENTED"}
]}
JSON
}

# The Step 1 lookup's payload, with a body long enough to prove the 3-line cut.
lookup_payload() {
  printf '%s' '{"state":"MERGED","number":225,"url":"https://x/225","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":null,"body":"one\ntwo\nthree\nfour"}'
}

# The Step 6 run-watch payload: one concluded run and one still pending, to
# prove the null-conclusion dash.
runs_payload() {
  printf '%s' '{"workflow_runs":[{"id":111,"status":"completed","conclusion":"success","html_url":"https://x/111"},{"id":222,"status":"in_progress","conclusion":null,"html_url":"https://x/222"}]}'
}

# ─── the programs are still where the tests look for them ──────────────────

@test "the poll's jq program is readable out of the skill" {
  [ -n "$(poll_jq)" ]
}

@test "the PR lookup's jq program is readable out of the skill" {
  [ -n "$(lookup_jq)" ]
}

# Each extractor must find its program in SKILL.md exactly once. Without this,
# a restructure that breaks a pattern leaves the extractor returning an empty
# string and the cases below grading nothing while still reporting green.
@test "each jq program and field list is extracted exactly once" {
  local out
  for extractor in poll_jq lookup_jq poll_json lookup_json watch_jq; do
    out="$("$extractor")"
    [ -n "$out" ] || fail "$extractor matched nothing in $SKILL"
    [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ] || fail "$extractor matched more than once in $SKILL"
  done
}

# ─── poll: leading values, in the order the prose promises ─────────────────

@test "poll: five values then the checks marker, in order" {
  run_poll '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  [ "${lines[0]}" = "MERGED" ]
  [ "${lines[1]}" = "deadbee" ]
  [ "${lines[2]}" = "f00" ]
  [ "${lines[3]}" = "armed" ]
  [ "${lines[4]}" = "UNKNOWN" ]
  [ "${lines[5]}" = "checks<<<" ]
}

@test "poll: an unmerged PR reports an empty merge commit rather than null, and reads as disarmed" {
  run_poll '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":null,"mergeStateStatus":"BLOCKED","statusCheckRollup":[]}'
  # Asserted whole: the empty merge commit is a real line the skill counts on,
  # and $lines drops it.
  [ "$output" = "$(printf 'OPEN\n\nf00\ndisarmed\nBLOCKED\nchecks<<<')" ]
}

@test "poll: autoMergeRequest survives the merge, which is why MERGED is read first" {
  run_poll '{"state":"MERGED","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":{"enabledAt":"x"},"mergeStateStatus":"UNKNOWN","statusCheckRollup":[]}'
  [ "${lines[0]}" = "MERGED" ]
  [ "${lines[3]}" = "armed" ]
}

# ─── poll: the failing-check allowlist ─────────────────────────────────────

@test "checks: every conclusion that is not a pass is reported" {
  run_poll "$(rollup)"
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

@test "checks: a conclusion GitHub has not defined yet reads as a failure, not a pass" {
  run_poll '{"statusCheckRollup":[{"name":"brand-new","status":"COMPLETED","conclusion":"NOT_YET_INVENTED"}]}'
  [[ "$output" == *"brand-new"* ]]
}

@test "checks: passing conclusions and states are never reported" {
  run_poll "$(rollup)"
  [[ "$output" != *"ok-success"* ]]
  [[ "$output" != *"ok-neutral"* ]]
  [[ "$output" != *"ok-skipped"* ]]
  [[ "$output" != *"ctx-success"* ]]
  [[ "$output" != *"ctx-expected"* ]]
}

@test "checks: a check still running is pending, not a failure" {
  run_poll "$(rollup)"
  [[ "$output" != *"pending-queued"* ]]
  [[ "$output" != *"pending-in-progress"* ]]
  [[ "$output" != *"pending-waiting"* ]]
  [[ "$output" != *"pending-requested"* ]]
  [[ "$output" != *"pending-pending"* ]]
  [[ "$output" != *"ctx-pending"* ]]
}

@test "checks: a name carrying a comma stays on one line" {
  run_poll '{"statusCheckRollup":[{"name":"lint, test and ship","status":"COMPLETED","conclusion":"FAILURE"}]}'
  [ "${lines[${#lines[@]}-1]}" = "lint, test and ship" ]
}

@test "checks: a PR with no checks at all emits the marker and nothing after it" {
  run_poll '{"state":"OPEN","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":null,"mergeStateStatus":"CLEAN","statusCheckRollup":null}'
  [ "$output" = "$(printf 'OPEN\n\nf00\ndisarmed\nCLEAN\nchecks<<<')" ]
}

# ─── the Step 1 lookup ─────────────────────────────────────────────────────

@test "lookup: six values then the body marker and three body lines" {
  run_lookup "$(lookup_payload)"
  [ "${lines[0]}" = "MERGED" ]
  [ "${lines[1]}" = "225" ]
  [ "${lines[2]}" = "https://x/225" ]
  [ "${lines[3]}" = "deadbee" ]
  [ "${lines[4]}" = "f00" ]
  [ "${lines[5]}" = "disarmed" ]
  [ "${lines[6]}" = "body<<<" ]
  [ "${lines[7]}" = "one" ]
  [ "${lines[9]}" = "three" ]
  [ "${#lines[@]}" -eq 10 ]
}

@test "lookup: a PR with no body still emits the marker, and a null body does not become the string null" {
  run_lookup '{"state":"OPEN","number":1,"url":"https://x/1","mergeCommit":null,"headRefOid":"f00","autoMergeRequest":null,"body":null}'
  [ "$output" = "$(printf 'OPEN\n1\nhttps://x/1\n\nf00\ndisarmed\nbody<<<')" ]
}

# ─── Step 6: the run-watch filter ───────────────────────────────────────────

@test "watch: emits four tab-separated fields per run, a dash for a null conclusion" {
  run jq -r "$(watch_jq)" <<<"$(runs_payload)"
  [ "$status" -eq 0 ]
  [ "${lines[0]}" = "$(printf '111\tcompleted\tsuccess\thttps://x/111')" ]
  [ "${lines[1]}" = "$(printf '222\tin_progress\t-\thttps://x/222')" ]
  [ "${#lines[@]}" -eq 2 ]
}

# ─── the --json list and the filter beside it still agree ──────────────────

@test "poll: the --json list carries every field the filter reads" {
  local full narrowed
  full="$(jq -r "$(poll_jq)" <<<"$(rollup)")"
  narrowed="$(jq -r "$(poll_jq)" <<<"$(narrow "$(rollup)" "$(poll_json)")")"
  [ "$full" = "$narrowed" ]
}

@test "lookup: the --json list carries every field the filter reads" {
  local full narrowed
  full="$(jq -r "$(lookup_jq)" <<<"$(lookup_payload)")"
  narrowed="$(jq -r "$(lookup_jq)" <<<"$(narrow "$(lookup_payload)" "$(lookup_json)")")"
  [ "$full" = "$narrowed" ]
}
