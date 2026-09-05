#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

TIMINGS="$DOTFILES_ROOT/bin/wf-cycle-timings"
IMPL="$DOTFILES_ROOT/agents/skills/wf-impl-review/SKILL.md"
SPEC="$DOTFILES_ROOT/agents/skills/wf-spec-review/SKILL.md"

# Source in library mode inside a subshell so its `set -euo pipefail` is
# contained, then invoke one function. Mirrors tests/wf-status.bats.
call() {
  run bash -c '_WF_CYCLE_TIMINGS_LIB_ONLY=1 source "$0"; "$@"' "$TIMINGS" "$@"
}

# iso <offset-seconds>: a UTC timestamp that many seconds after a fixed epoch,
# in the millisecond-bearing form the real transcripts use. The fractional part
# is deliberate - fromdateiso8601 rejects it, so every fixture exercises the
# strip that production code has to do.
iso() {
  python3 -c "import sys,datetime as d; print((d.datetime(2026,9,4,20,0,0,tzinfo=d.timezone.utc)+d.timedelta(seconds=int(sys.argv[1]))).strftime('%Y-%m-%dT%H:%M:%S.268Z'))" "$1"
}

# rec <offset> <type> [content]: one JSONL record.
rec() {
  local content="${3:-}"
  jq -cn --arg t "$(iso "$1")" --arg ty "$2" --arg c "$content" \
    '{timestamp:$t, type:$ty} + (if $c == "" then {} else {message:{content:$c}} end)'
}

# reviewer <dir> <id> <name> <kind>: a meta.json plus an empty transcript.
reviewer() {
  jq -cn --arg d "$4 review: $3" '{agentType:"claude", description:$d, spawnDepth:1}' \
    > "$1/agent-$2.meta.json"
  : > "$1/agent-$2.jsonl"
}

FT="You're not obligated to, but you can now make changes on this branch."

@test "phases: read-only ends at the reviewer's own last activity, not at the follow-through" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  {
    rec 0 user "opening prompt"
    rec 600 assistant
    rec 900 assistant
    rec 1127 user "The coordinator sent a message while you were working:
$FT"
    rec 1500 assistant
  } > "$dir/agent-aaa.jsonl"
  call phases "$dir/agent-aaa.jsonl"
  [ "$status" -eq 0 ]
  # read-only 900, follow 373, total 1500, turnaround 227.
  # The 227s between the reviewer's last output and the follow-through is
  # coordinator turnaround and belongs to neither phase - this is the Darius
  # case that makes the baseline 84m55s rather than 80m19s.
  [ "$output" = "900 373 1500 227" ]
}

@test "phases: no follow-through means the whole run is read-only" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  { rec 0 user "opening prompt"; rec 480 assistant; } > "$dir/agent-bbb.jsonl"
  call phases "$dir/agent-bbb.jsonl"
  [ "$output" = "480 0 480 0" ]
}

@test "phases: records out of timestamp order still yield the right bounds" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  { rec 900 assistant; rec 0 user "opening prompt"; rec 600 assistant; } > "$dir/agent-ccc.jsonl"
  call phases "$dir/agent-ccc.jsonl"
  [ "$output" = "900 0 900 0" ]
}

@test "phases: unparseable lines are skipped rather than aborting the run" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  { rec 0 user "opening prompt"; echo 'not json at all'; rec 300 assistant; } > "$dir/agent-ddd.jsonl"
  call phases "$dir/agent-ddd.jsonl"
  [ "$status" -eq 0 ]
  [ "$output" = "300 0 300 0" ]
}

@test "phases: a record with no timestamp is ignored" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  { rec 0 user "opening prompt"; echo '{"type":"summary"}'; rec 300 assistant; } > "$dir/agent-eee.jsonl"
  call phases "$dir/agent-eee.jsonl"
  [ "$output" = "300 0 300 0" ]
}

@test "reviewers: depth-1 review agents are listed, nested and non-review agents are not" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  reviewer "$dir" aaa Alia Impl
  reviewer "$dir" bbb Bheem Impl
  jq -cn '{agentType:"general-purpose", description:"Digest prior reviews", spawnDepth:2, parentAgentId:"aaa"}' \
    > "$dir/agent-nnn.meta.json"
  : > "$dir/agent-nnn.jsonl"
  jq -cn '{agentType:"claude", description:"Something unrelated", spawnDepth:1}' \
    > "$dir/agent-zzz.meta.json"
  : > "$dir/agent-zzz.jsonl"
  call reviewers "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'aaa\tAlia\nbbb\tBheem')" ]
}

@test "reviewers: a spec review roster is recognised too" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  reviewer "$dir" aaa Cristo Spec
  call reviewers "$dir"
  [ "$output" = "$(printf 'aaa\tCristo')" ]
}

@test "reviewers: roster is ordered by transcript start time, not by agent id" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  # zzz's id sorts after aaa's, but zzz's transcript starts first - the roster
  # must follow the transcript, not the filename.
  reviewer "$dir" zzz Zoe Impl
  reviewer "$dir" aaa Amir Impl
  rec 0 user "opening prompt" > "$dir/agent-zzz.jsonl"
  rec 600 user "opening prompt" > "$dir/agent-aaa.jsonl"
  call reviewers "$dir"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'zzz\tZoe\naaa\tAmir')" ]
}

@test "fmt_duration renders minutes and zero-padded seconds" {
  call fmt_duration 227
  [ "$output" = "3m47s" ]
  call fmt_duration 4819
  [ "$output" = "80m19s" ]
  call fmt_duration 8
  [ "$output" = "0m08s" ]
}

@test "subagents_dir accepts a session directory or the subagents directory itself" {
  local session="$BATS_TEST_TMPDIR/session"
  mkdir -p "$session/subagents"
  call subagents_dir "$session"
  [ "$output" = "$session/subagents" ]
  call subagents_dir "$session/subagents"
  [ "$output" = "$session/subagents" ]
}

@test "a directory with no reviewer transcripts exits 2 and says so" {
  local dir="$BATS_TEST_TMPDIR/empty"
  mkdir -p "$dir/subagents"
  run "$TIMINGS" "$dir"
  [ "$status" -eq 2 ]
  [[ "$output" == *"no reviewer transcript"* ]]
}

@test "--help prints usage and exits 0" {
  run "$TIMINGS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage:"* ]]
}

@test "no arguments is a usage error" {
  run "$TIMINGS"
  [ "$status" -eq 2 ]
}

# ─── the follow-through marker still matches both skills ───────────────────
#
# Phase detection works by finding the follow-through prompt's text inside a
# reviewer transcript. That text lives in the two SKILL.md files, so the script
# and the skills are joined at a string, and a reworded follow-through would
# silently make every read-only phase span the whole run rather than failing.
# Pinned here the way tests/wf-wrap-gh-jq.bats pins a jq program against the
# SKILL.md it still lives in.

marker_from_script() {
  sed -n 's/^FOLLOWTHROUGH_MARKER="\(.*\)"$/\1/p' "$TIMINGS"
}

@test "the follow-through marker is extractable from the script exactly once" {
  local m
  m="$(marker_from_script)"
  [ -n "$m" ]
  [ "$(printf '%s\n' "$m" | wc -l | tr -d ' ')" -eq 1 ]
}

@test "the follow-through marker appears exactly once in each review skill" {
  local m impl spec
  m="$(marker_from_script)"
  impl="$(grep -c -F "$m" "$IMPL" || true)"
  spec="$(grep -c -F "$m" "$SPEC" || true)"
  [ "$impl" = "1" ] || fail "marker found $impl times in $IMPL, expected 1"
  [ "$spec" = "1" ] || fail "marker found $spec times in $SPEC, expected 1"
}
