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

# capture <fn> [args...]: the same, but returning the output for use as an
# argument to another function rather than through $output.
capture() {
  bash -c '_WF_CYCLE_TIMINGS_LIB_ONLY=1 source "$0"; "$@"' "$TIMINGS" "$@"
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
  # case that keeps the baseline at 80m19s. Folding turnaround into read-only
  # instead is what produced the discarded 84m55s figure.
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

# nested_agent <dir> <id> <parent> <description> <start> <end>: a depth-2
# agent under one reviewer, with a transcript spanning those two offsets.
nested_agent() {
  jq -cn --arg d "$4" --arg p "$3" \
    '{agentType:"general-purpose", description:$d, spawnDepth:2, parentAgentId:$p}' \
    > "$1/agent-$2.meta.json"
  { rec "$5" user "go"; rec "$6" assistant; } > "$1/agent-$2.jsonl"
}

# two_round_cycle <dir>: two reviewers, one nested spawn on each side of the
# follow-through, and one inter-round gap between them. Every duration is
# distinct, so no field of a porcelain row can come out right by coincidence.
#
#   Alia   0 .. 600 read-only, follow-through at 700, 1000 last  (gap 120)
#     nested 400 .. 460, before her follow-through
#   Bheem  1120 .. 1400 read-only, follow-through at 1500, 1800 last
#     nested 1600 .. 1700, after his
two_round_cycle() {
  mkdir -p "$1"
  reviewer "$1" aaa Alia Impl
  reviewer "$1" bbb Bheem Impl
  {
    rec 0 user "opening prompt"
    rec 300 assistant
    rec 600 assistant
    rec 700 user "The coordinator sent a message while you were working:
$FT"
    rec 1000 assistant
  } > "$1/agent-aaa.jsonl"
  {
    rec 1120 user "opening prompt"
    rec 1400 assistant
    rec 1500 user "The coordinator sent a message while you were working:
$FT"
    rec 1800 assistant
  } > "$1/agent-bbb.jsonl"
  nested_agent "$1" n1 aaa "Digest prior reviews" 400 460
  nested_agent "$1" n2 bbb "Recheck the suite" 1600 1700
}

@test "--porcelain emits every row type, with each nested spawn in its own phase" {
  local dir="$BATS_TEST_TMPDIR/sub"
  two_round_cycle "$dir"
  run "$TIMINGS" --porcelain "$dir"
  [ "$status" -eq 0 ]
  local expected
  expected="$(
    printf 'reviewer\t%s\t%d\t%d\t%d\t%d\n' Alia 600 300 1000 100
    printf 'reviewer\t%s\t%d\t%d\t%d\t%d\n' Bheem 280 300 680 100
    printf 'nested\t%s\t%s\t%d\t%s\n' Alia 'Digest prior reviews' 60 read-only
    printf 'nested\t%s\t%s\t%d\t%s\n' Bheem 'Recheck the suite' 100 follow
    printf 'gap\t%s\t%s\t%d\n' Alia Bheem 120
    printf 'totals\t%d\t%d\t%d\t%d\t%d\n' 880 600 1480 1800 120
  )"
  [ "$output" = "$expected" ] || fail "porcelain output drifted:
$output"
}

@test "a nested spawn's phase follows the parent's follow-through, not a constant" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  reviewer "$dir" aaa Alia Impl
  {
    rec 0 user "opening prompt"
    rec 600 assistant
    rec 700 user "The coordinator sent a message while you were working:
$FT"
    rec 1800 assistant
  } > "$dir/agent-aaa.jsonl"
  local ft
  ft="$(capture followthrough "$dir/agent-aaa.jsonl")"
  # Same reviewer, same child duration, one on each side of that boundary.
  nested_agent "$dir" n1 aaa "Before" 400 500
  call nested "$dir" aaa "$ft"
  [ "$output" = "$(printf 'Before\t100\tread-only')" ]
  nested_agent "$dir" n1 aaa "After" 900 1000
  call nested "$dir" aaa "$ft"
  [ "$output" = "$(printf 'After\t100\tfollow')" ]
}

@test "a reviewer that never got a follow-through has no follow phase to spawn into" {
  local dir="$BATS_TEST_TMPDIR/sub"
  mkdir -p "$dir"
  reviewer "$dir" aaa Alia Impl
  { rec 0 user "opening prompt"; rec 1800 assistant; } > "$dir/agent-aaa.jsonl"
  local ft
  ft="$(capture followthrough "$dir/agent-aaa.jsonl")"
  [ "$ft" = "0" ]
  # phases() calls the whole run read-only, so a spawn under it is read-only
  # too, however late it started.
  nested_agent "$dir" n1 aaa "Late but still read-only" 1700 1750
  call nested "$dir" aaa "$ft"
  [ "$output" = "$(printf 'Late but still read-only\t50\tread-only')" ]
}

@test "the human-readable summary splits nested spawns by phase" {
  local dir="$BATS_TEST_TMPDIR/sub"
  two_round_cycle "$dir"
  run "$TIMINGS" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"nested     read-only 1 spawn(s), 1m00s; follow 1 spawn(s), 1m40s"* ]] \
    || fail "summary line mixes phases or changed shape:
$output"
  # The per-spawn lines have to agree with the porcelain rows above.
  local line
  line="$(printf '%s\n' "$output" | grep -F 'Digest prior reviews')"
  [[ "$line" == *read-only* ]] || fail "read-only spawn not labelled: $line"
  line="$(printf '%s\n' "$output" | grep -F 'Recheck the suite')"
  [[ "$line" == *follow* ]] || fail "follow spawn not labelled: $line"
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
