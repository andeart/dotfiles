#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SCRIPT="$DOTFILES_ROOT/claude/statusline-command.sh"

# A status line payload with the existing segments populated but no effort field.
# ctx used = 1000 + 2000 + 3000 = 6000 -> "6k"; size 200000 -> "200k".
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

@test "attaches the effort to the model as a diamond, with no separator before it" {
  run_statusline "$(base_payload | jq '.effort.level = "high"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == "Opus 4.8 ◇ high │"* ]]
}

@test "renders the effort in the same orange as the model name, whatever the level" {
  for level in low medium high xhigh max; do
    run_statusline "$(base_payload | jq --arg l "$level" '.effort.level = $l')"
    [ "$status" -eq 0 ]
    if [[ "$output" != *$'\033[38;5;173m◇ '"$level"* ]]; then
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

@test "trims the redundant 'context' from a 1M context model name" {
  run_statusline "$(base_payload | jq '.model.display_name = "Opus 4.8 (1M context)"')"
  [ "$status" -eq 0 ]
  local plain
  plain="$(printf '%s' "$output" | strip_ansi)"
  [[ "$plain" == "Opus 4.8 (1M) │"* ]]
  [[ "$plain" != *context* ]]
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
    [[ "$plain" == *"6k/200k"* ]]    # context used/size
  done
}
