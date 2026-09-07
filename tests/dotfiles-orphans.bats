#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# A world whose mapping covers agents/AGENTS.md and nothing else, so every other
# manifest key is an orphan by construction.
#
# Extra arguments are manifest paths to record, relative to the fake home. They
# are relative because $TEST_LIVE is set by make_tmp_world below, so an absolute
# argument would be expanded at the call site against whatever the previous test
# left behind.
#
# Whether one exists on disk is left to the caller: the report's whole job is
# telling a key whose file is still there from one whose file has already gone.
orphan_world() {
  make_tmp_world
  cp "$TEST_REPO/agents/AGENTS.md" "$TEST_LIVE/.agents/AGENTS.md"
  local hash
  hash="$(shasum -a 256 "$TEST_REPO/agents/AGENTS.md" | awk '{print $1}')"

  local jqargs=(--arg covered "$TEST_LIVE/.agents/AGENTS.md" --arg h "$hash")
  local filter='{($covered): $h}'
  local i=0 p
  for p in "$@"; do
    jqargs+=(--arg "k$i" "$TEST_LIVE/$p")
    filter="$filter + {(\$k$i): \"stale\"}"
    i=$((i + 1))
  done
  jq -n "${jqargs[@]}" "$filter" > "$TEST_STATE"
}

_env() {
  env \
    DOTFILES_ROOT_OVERRIDE="$TEST_REPO" \
    DOTFILES_HOME_OVERRIDE="$TEST_LIVE" \
    DOTFILES_STATE_FILE="$TEST_STATE" \
    DOTFILES_MAPPING_OVERRIDE="agents/AGENTS.md|~/.agents/AGENTS.md" \
    "$@"
}

run_dotfiles() { run _env "$DOTFILES_BIN" "$@"; }
run_test_bin() { run _env "$DOTFILES_TEST_BIN" "$@"; }

# The `tmp=$(mktemp) && jq ...` line out of an orphans report. Takes the report
# as an argument rather than reading $output, which any intervening `run` in the
# same test would already have replaced.
manifest_command() {
  printf '%s\n' "$1" | grep -F 'tmp=$(mktemp)'
}

# ─── _orphan_keys ───────────────────────────────────────────────────────────────

@test "_orphan_keys names a manifest key the mapping no longer covers" {
  orphan_world ".claude/retired-hook.sh"
  run_test_bin orphan_keys
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_LIVE/.claude/retired-hook.sh" ]
}

@test "_orphan_keys says nothing when every key is still covered" {
  orphan_world
  run_test_bin orphan_keys
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "_orphan_keys says nothing when no manifest exists yet" {
  orphan_world
  command mv "$TEST_STATE" "$TEST_STATE.away"
  run_test_bin orphan_keys
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── status surfaces them, without calling them drift ───────────────────────────

# push and freeze both work off the mapping, so neither can reconcile a path
# that has left it. Counting an orphan as drift would point the summary at two
# commands that cannot act on it.
@test "status lists orphans without counting them as drift" {
  orphan_world ".claude/retired-hook.sh"
  run_dotfiles status
  [ "$status" -eq 0 ]
  [[ "$output" == *"orphaned"* ]]
  [[ "$output" == *"retired-hook.sh"* ]]
  [[ "$output" == *"run 'dotfiles orphans'"* ]]
  [[ "$output" == *"All clean"* ]]
}

@test "status counts the orphans it found" {
  orphan_world ".claude/a.sh" ".claude/b.sh"
  run_dotfiles status
  [ "$status" -eq 0 ]
  [[ "$output" == *"2 manifest key(s) no longer covered"* ]]
}

@test "status says nothing about orphans when there are none" {
  orphan_world
  run_dotfiles status
  [ "$status" -eq 0 ]
  [[ "$output" != *"orphaned"* ]]
  [[ "$output" != *"dotfiles orphans"* ]]
}

# ─── the orphans report ─────────────────────────────────────────────────────────

@test "orphans separates a key whose file survives from one whose file is gone" {
  orphan_world ".claude/still-here.sh" ".claude/long-gone.sh"
  echo "stale" > "$TEST_LIVE/.claude/still-here.sh"
  run_dotfiles orphans
  [ "$status" -eq 0 ]
  [[ "$output" == *"file + key"*"still-here.sh"* ]]
  [[ "$output" == *"key only"*"long-gone.sh"* ]]
}

@test "orphans prints no deletion command when only keys remain" {
  orphan_world ".claude/long-gone.sh"
  run_dotfiles orphans
  [ "$status" -eq 0 ]
  [[ "$output" != *"delete the files yourself"* ]]
  [[ "$output" == *"drop the manifest keys"* ]]
}

# AGENTS.md requires deletions be handed over, and an unreachable key is not
# proof the file was meant to go: a mapping entry commented out for an afternoon
# produces exactly the same one.
@test "orphans deletes nothing and leaves the manifest alone" {
  orphan_world ".claude/still-here.sh"
  echo "stale" > "$TEST_LIVE/.claude/still-here.sh"
  local before
  before="$(cat "$TEST_STATE")"
  run_dotfiles orphans
  [ "$status" -eq 0 ]
  [ -f "$TEST_LIVE/.claude/still-here.sh" ]
  [ "$(cat "$TEST_STATE")" = "$before" ]
}

@test "orphans reports none when the mapping covers everything" {
  orphan_world
  run_dotfiles orphans
  [ "$status" -eq 0 ]
  [[ "$output" == *"none."* ]]
}

# ─── the printed commands have to actually work ─────────────────────────────────

@test "the printed manifest command removes exactly the orphaned keys" {
  orphan_world ".claude/a.sh" ".claude/b.sh"
  run_dotfiles orphans
  [ "$status" -eq 0 ]

  eval "$(manifest_command "$output")"

  run jq -r 'keys[]' "$TEST_STATE"
  [ "$status" -eq 0 ]
  [ "$output" = "$TEST_LIVE/.agents/AGENTS.md" ]
}

# A live path is arbitrary bytes. Interpolating one into a single-quoted jq
# filter ends the quoting early on the first apostrophe and hands over a command
# that does not parse, so the keys travel as argv and the filter stays fixed.
@test "the printed commands survive a path containing a quote" {
  orphan_world ".claude/we'ird name.sh"
  echo "stale" > "$TEST_LIVE/.claude/we'ird name.sh"
  run_dotfiles orphans
  [ "$status" -eq 0 ]
  local report="$output"

  # The deletion line is handed over, never run, so it is graded on parsing.
  run bash -n <<< "$(printf '%s\n' "$report" | grep -F 'delete the files' -A1 | tail -1)"
  [ "$status" -eq 0 ]

  eval "$(manifest_command "$report")"
  run jq -r 'keys[]' "$TEST_STATE"
  [ "$output" = "$TEST_LIVE/.agents/AGENTS.md" ]
}
