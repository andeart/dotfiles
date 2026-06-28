#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

FMT_BIN="$DOTFILES_ROOT/bin/claude-format-settings"

# Fresh tmp dir per test. Sets:
#   $WORK — scratch root
#   $FILE — an unformatted settings JSON file inside $WORK
# The fixture has out-of-order, mixed-case allow/deny entries, a duplicate in
# allow, and out-of-order enabledPlugins keys.
setup() {
  WORK="$(mktemp -d)"
  FILE="$WORK/settings.json"
  cat > "$FILE" <<'EOF'
{
  "permissions": {
    "allow": ["Zebra", "apple", "Zebra"],
    "deny": ["bravo", "Alpha"]
  },
  "enabledPlugins": { "zoo": true, "Ant": true }
}
EOF
}

# ─── formatting a file ─────────────────────────────────────────────────────────

@test "sorts allow/deny case-insensitively and dedupes in place" {
  run "$FMT_BIN" "$FILE"
  [ "$status" -eq 0 ]
  [ "$(jq -c '.permissions.allow' "$FILE")" = '["apple","Zebra"]' ]
  [ "$(jq -c '.permissions.deny' "$FILE")" = '["Alpha","bravo"]' ]
}

@test "sorts enabledPlugins keys case-insensitively" {
  run "$FMT_BIN" "$FILE"
  [ "$status" -eq 0 ]
  [ "$(jq -rc '.enabledPlugins | keys_unsorted | @csv' "$FILE")" = '"Ant","zoo"' ]
}

@test "reports duplicate entries it removed" {
  run "$FMT_BIN" "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"duplicate permissions.allow entries:"* ]]
  [[ "$output" == *"Zebra"* ]]
}

@test "an already-formatted file is left unchanged and reported" {
  "$FMT_BIN" "$FILE"
  before="$(cat "$FILE")"
  run "$FMT_BIN" "$FILE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already formatted"* ]]
  [ "$(cat "$FILE")" = "$before" ]
}

# ─── directory resolution ──────────────────────────────────────────────────────

@test "a directory argument resolves to .claude/settings.local.json under it" {
  mkdir -p "$WORK/proj/.claude"
  mv "$FILE" "$WORK/proj/.claude/settings.local.json"
  run "$FMT_BIN" "$WORK/proj"
  [ "$status" -eq 0 ]
  target="$WORK/proj/.claude/settings.local.json"
  [[ "$output" == *"$target"* ]]
  [ "$(jq -c '.permissions.allow' "$target")" = '["apple","Zebra"]' ]
}

@test "a directory argument tolerates a trailing slash" {
  mkdir -p "$WORK/proj/.claude"
  mv "$FILE" "$WORK/proj/.claude/settings.local.json"
  run "$FMT_BIN" "$WORK/proj/"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/proj/.claude/settings.local.json"* ]]
}

@test "a directory with no .claude/settings.local.json is an error" {
  mkdir -p "$WORK/empty"
  run "$FMT_BIN" "$WORK/empty"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no .claude/settings.local.json found under directory"* ]]
}

# ─── --check ───────────────────────────────────────────────────────────────────

@test "--check exits 1 and does not modify a file needing formatting" {
  before="$(cat "$FILE")"
  run "$FMT_BIN" --check "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"needs formatting"* ]]
  [ "$(cat "$FILE")" = "$before" ]
}

@test "--check exits 0 on an already-formatted file" {
  "$FMT_BIN" "$FILE"
  run "$FMT_BIN" --check "$FILE"
  [ "$status" -eq 0 ]
}

# ─── resilience / error handling ───────────────────────────────────────────────

@test "a nonexistent path is an error" {
  run "$FMT_BIN" "$WORK/nope.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
}

@test "an empty file is an error rather than a jq parse failure" {
  : > "$WORK/empty.json"
  run "$FMT_BIN" "$WORK/empty.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"is empty"* ]]
}

@test "invalid JSON is reported and the file is left untouched" {
  printf '{bad\n' > "$WORK/bad.json"
  before="$(cat "$WORK/bad.json")"
  run "$FMT_BIN" "$WORK/bad.json"
  [ "$status" -eq 1 ]
  [[ "$output" == *"failed to parse"* ]]
  [ "$(cat "$WORK/bad.json")" = "$before" ]
}

@test "a non-writable file needing formatting is reported, not truncated" {
  chmod 444 "$FILE"
  before="$(cat "$FILE")"
  run "$FMT_BIN" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not writable"* ]]
  [ "$(cat "$FILE")" = "$before" ]
}

@test "a bad path does not stop a later good path from being formatted" {
  run "$FMT_BIN" "$WORK/nope.json" "$FILE"
  [ "$status" -eq 1 ]
  [[ "$output" == *"does not exist"* ]]
  [ "$(jq -c '.permissions.allow' "$FILE")" = '["apple","Zebra"]' ]
}

# ─── usage / options ───────────────────────────────────────────────────────────

@test "--help exits 0 and documents directory behavior" {
  run "$FMT_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"settings.local.json"* ]]
}

@test "an unknown option exits 2" {
  run "$FMT_BIN" --bogus "$FILE"
  [ "$status" -eq 2 ]
}

@test "no paths exits 2" {
  run "$FMT_BIN"
  [ "$status" -eq 2 ]
}
