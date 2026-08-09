#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SCRIPT="$DOTFILES_ROOT/claude/statusline-command.sh"

# A status line payload with the existing segments populated but no effort field.
# ctx used = 1000 + 2000 + 3000 = 6000 -> 6 thousand -> "⁶ᴷ" in the bar.
base_payload() {
  cat <<'JSON'
{
  "model": { "display_name": "Opus 4.8" },
  "context_window": {
    "used_percentage": 42,
    "context_window_size": 200000,
    "current_usage": {
      "input_tokens": 1000,
      "cache_creation_input_tokens": 2000,
      "cache_read_input_tokens": 3000
    }
  },
  "rate_limits": {
    "five_hour": { "used_percentage": 10, "resets_at": 0 },
    "seven_day": { "used_percentage": 20, "resets_at": 0 }
  }
}
JSON
}

# Feed a JSON payload into the status line script. Sets $output/$status via `run`.
run_statusline() {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$1" "$SCRIPT"
}

# Drop ANSI SGR sequences so assertions can match on visible text.
strip_ansi() {
  sed $'s/\x1b\\[[0-9;]*m//g'
}

# ─── reasoning effort is shown ──────────────────────────────────────────────────

@test "shows the reasoning effort when present in the input" {
  run_statusline "$(base_payload | jq '.effort.level = "high"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == *high* ]]
}

@test "attaches the effort directly to the model, with no separator before it" {
  run_statusline "$(base_payload | jq '.effort.level = "high"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == "Opus 4.8 high │"* ]]
}

@test "renders the effort in the same orange as the model name, whatever the level" {
  for level in low medium high xhigh max; do
    run_statusline "$(base_payload | jq --arg l "$level" '.effort.level = $l')"
    [ "$status" -eq 0 ]
    if [[ "$output" != *$'\033[38;5;173m'"$level"* ]]; then
      echo "expected effort '$level' in model orange (173): $output"
      return 1
    fi
  done
}

@test "reflects the exact effort value in effect for the session" {
  for level in low medium high xhigh max; do
    run_statusline "$(base_payload | jq --arg l "$level" '.effort.level = $l')"
    [ "$status" -eq 0 ]
    local plain
    plain="$(printf '%s' "$output" | strip_ansi)"
    if [[ "$plain" != *"$level"* ]]; then
      echo "expected effort '$level' in output: $plain"
      return 1
    fi
  done
}

# ─── graceful degradation when effort is absent ─────────────────────────────────

@test "omits the effort segment when the input has no effort field" {
  run_statusline "$(base_payload)"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  for level in low medium high xhigh max; do
    if [[ "$plain" == *"$level"* ]]; then
      echo "did not expect effort text '$level' in output: $plain"
      return 1
    fi
  done
}

@test "omits the effort segment when the effort object has no level" {
  run_statusline "$(base_payload | jq '.effort = {}')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  for level in low medium high xhigh max; do
    if [[ "$plain" == *"$level"* ]]; then
      echo "did not expect effort text '$level' in output: $plain"
      return 1
    fi
  done
}

# ─── model name ─────────────────────────────────────────────────────────────────

@test "reduces a 1M context model name to a bare size suffix" {
  run_statusline "$(base_payload | jq '.model.display_name = "Opus 4.8 (1M context)"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" != *context* ]]
  [[ "$plain" == "Opus 4.8 1M │"* ]]
}

@test "leaves a parenthetical that is not a context size intact" {
  run_statusline "$(base_payload | jq '.model.display_name = "Opus 4.8 (beta)"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == "Opus 4.8 (beta) │"* ]]
}

@test "leaves a model name without a context suffix unchanged" {
  run_statusline "$(base_payload | jq '.model.display_name = "Sonnet 5"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == "Sonnet 5 │"* ]]
}

# ─── existing segments stay intact ──────────────────────────────────────────────

@test "keeps the existing model, context, and rate-limit segments intact" {
  for payload in "$(base_payload)" "$(base_payload | jq '.effort.level = "high"')"; do
    run_statusline "$payload"
    [ "$status" -eq 0 ]
    local plain
    plain="$(printf '%s' "$output" | strip_ansi)"
    [[ "$plain" == *"Opus 4.8"* ]]  # model name
    [[ "$plain" == *"5h"* ]]         # five-hour rate-limit key
    [[ "$plain" == *"7d"* ]]         # seven-day rate-limit key
    [[ "$plain" == *"⁶ᴷ"* ]]         # context usage in thousands
  done
}

# ─── worktree lines ─────────────────────────────────────────────────────────────

# Line labels, as UTF-8 byte escapes so they stay legible in editors that render
# private-use glyphs as tofu:
#   U+F418 oct-git_branch, U+F413 oct-file_directory
GLYPH_BRANCH=$'\357\220\230'
GLYPH_DIR=$'\357\220\223'

# Build a repo with a linked worktree whose directory name and branch name
# differ, which is the shape Claude Code's EnterWorktree produces: the worktree
# registers as "feature-x" while its branch is "worktree-feature-x". Sets:
#   $WT_BASE — the main working tree of the clone
#   $WT_DIR  — the linked worktree, under .claude/worktrees/
make_worktree_world() {
  local parent
  parent="$(mktemp -d)"
  WT_BASE="$parent/base"
  WT_DIR="$WT_BASE/.claude/worktrees/feature-x"

  git init -q "$WT_BASE"
  git -C "$WT_BASE" config user.email t@t.t
  git -C "$WT_BASE" config user.name t
  git -C "$WT_BASE" config commit.gpgsign false
  git -C "$WT_BASE" commit -q --allow-empty -m init
  git -C "$WT_BASE" branch -M main
  git -C "$WT_BASE" worktree add -q "$WT_DIR" -b worktree-feature-x
}

# base_payload with a workspace pointing at $1. git_worktree is populated the way
# Claude Code populates it — with the worktree's registered name — so the tests
# below prove the branch comes from git rather than from that field.
worktree_payload() {
  base_payload | jq --arg d "$1" --arg n "$(basename "$1")" \
    '.workspace = {current_dir: $d, git_worktree: $n}'
}

# The one status line labelled with glyph $1, drawn from captured output $2.
line_with_glyph() {
  printf '%s' "$2" | strip_ansi | grep -F "$1"
}

count_lines() {
  printf '%s\n' "$1" | wc -l | tr -d ' '
}

@test "reports the branch a linked worktree is on, not its registered name" {
  make_worktree_world
  run_statusline "$(worktree_payload "$WT_DIR")"
  [ "$status" -eq 0 ]
  local branch_line
  branch_line="$(line_with_glyph "$GLYPH_BRANCH" "$output")"
  [[ "$branch_line" == *"worktree-feature-x"* ]]
}

@test "gives the worktree's registered name no line of its own" {
  make_worktree_world
  run_statusline "$(worktree_payload "$WT_DIR")"
  [ "$status" -eq 0 ]
  # The path line ends in the registered name, so the only other mention would
  # be a line dedicated to it.
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [ "$(printf '%s' "$plain" | grep -c -- 'feature-x')" -eq 2 ]  # branch + path
}

@test "gives the branch and the path a line each, branch first" {
  make_worktree_world
  run_statusline "$(worktree_payload "$WT_DIR")"
  [ "$status" -eq 0 ]
  [ "$(count_lines "$output")" -eq 3 ]  # status line + branch + path
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$(printf '%s' "$plain" | sed -n 2p)" == *"$GLYPH_BRANCH"* ]]
  [[ "$(printf '%s' "$plain" | sed -n 3p)" == *"$GLYPH_DIR"* ]]
}

@test "falls back to a short SHA when the worktree HEAD is detached" {
  make_worktree_world
  git -C "$WT_DIR" checkout -q --detach
  local sha
  sha="$(git -C "$WT_DIR" rev-parse --short HEAD)"
  run_statusline "$(worktree_payload "$WT_DIR")"
  [ "$status" -eq 0 ]
  local branch_line
  branch_line="$(line_with_glyph "$GLYPH_BRANCH" "$output")"
  [[ "$branch_line" == *"detached $sha"* ]]
  [[ "$branch_line" != *"detached ?"* ]]
}

@test "stays on one line in the main working tree of a normal clone" {
  make_worktree_world
  run_statusline "$(worktree_payload "$WT_BASE")"
  [ "$status" -eq 0 ]
  [ "$(count_lines "$output")" -eq 1 ]
}

@test "stays on one line when the payload carries no workspace at all" {
  run_statusline "$(base_payload)"
  [ "$status" -eq 0 ]
  [ "$(count_lines "$output")" -eq 1 ]
}
