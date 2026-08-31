#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-wrap/SKILL.md"

# The Step 1 lookup's jq program is read out of SKILL.md rather than copied
# here. The skill is the only place it exists - nothing executes that file -
# so a copy would grade a stale expression and pass while the real one
# rotted. This sed-out-of-markdown extraction is the one place that still
# needs it: the lookup is a one-shot command with nowhere else to live, unlike
# Step 1a's poll and Step 6's watch, which are executable scripts under
# agents/skills/wf-wrap/scripts/ and get tested by running them directly (see
# await-auto-merge.bats and watch-post-merge-ci.bats).

lookup_jq() {
  sed -n "s/^gh pr view --json .*--jq '\(.*\)'\$/\1/p" "$SKILL"
}

# The --json field list beside the filter. gh returns only the fields it was
# asked for and jq answers null for the rest, so the two halves of one command
# can drift apart without either erroring.
lookup_json() {
  sed -n "s/^gh pr view --json \([^ ]*\) --jq .*/\1/p" "$SKILL"
}

# narrow <json> <field list>: the payload gh would actually hand back for that
# --json list - only those top-level keys.
narrow() {
  jq -c --arg keys "$2" 'with_entries(select(.key as $k | ($keys | split(",")) | index($k)))' <<<"$1"
}

run_lookup() {
  run jq -r "$(lookup_jq)" <<<"$1"
  [ "$status" -eq 0 ]
}

# The Step 1 lookup's payload, with a body long enough to prove the 3-line cut.
lookup_payload() {
  printf '%s' '{"state":"MERGED","number":225,"url":"https://x/225","mergeCommit":{"oid":"deadbee"},"headRefOid":"f00","autoMergeRequest":null,"body":"one\ntwo\nthree\nfour"}'
}

# ─── the program is still where the tests look for it ──────────────────────

@test "the PR lookup's jq program is readable out of the skill" {
  [ -n "$(lookup_jq)" ]
}

# Each extractor must find its program in SKILL.md exactly once. Without this,
# a restructure that breaks the pattern leaves the extractor returning an
# empty string and the cases below grading nothing while still reporting
# green.
@test "each jq program and field list is extracted exactly once" {
  local out
  for extractor in lookup_jq lookup_json; do
    out="$("$extractor")"
    [ -n "$out" ] || fail "$extractor matched nothing in $SKILL"
    [ "$(printf '%s\n' "$out" | wc -l | tr -d ' ')" -eq 1 ] || fail "$extractor matched more than once in $SKILL"
  done
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

# ─── the --json list and the filter beside it still agree ──────────────────

@test "lookup: the --json list carries every field the filter reads" {
  local full narrowed
  full="$(jq -r "$(lookup_jq)" <<<"$(lookup_payload)")"
  narrowed="$(jq -r "$(lookup_jq)" <<<"$(narrow "$(lookup_payload)" "$(lookup_json)")")"
  [ "$full" = "$narrowed" ]
}
