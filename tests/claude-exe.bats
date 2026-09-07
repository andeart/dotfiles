#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

LIB="$DOTFILES_ROOT/claude/hooks/lib/claude-exe.sh"

BUNDLED="/Users/me/Library/Application Support/Claude/claude-code/2.1.260/claude.app/Contents/MacOS/claude"
BARE="/Users/me/.local/share/claude/versions/2.1.263"

# ─── is_bundled_claude ──────────────────────────────────────────────────────────

@test "is_bundled_claude accepts bundle paths and rejects everything else" {
  source "$LIB"
  is_bundled_claude "$BUNDLED" || fail "expected the desktop app path to read as bundled"
  is_bundled_claude "/Applications/Claude.app/Contents/MacOS/claude" || fail "expected /Applications bundle"

  ! is_bundled_claude "$BARE" || fail "expected the bare CLI path to read as unbundled"
  ! is_bundled_claude "" || fail "expected an unresolved path to read as unbundled"
  ! is_bundled_claude "/Users/me/claude.app/Contents/Resources/claude" || fail "MacOS/ is the part that matters"
}

# ─── lsof parsing ───────────────────────────────────────────────────────────────

# The desktop app's copy lives under "Application Support". lsof's default table
# puts NAME last but not as the last whitespace-delimited field, so reading $NF
# returned a path that does not exist - and the value is both what decides the
# verdict and what a caller shows the user.
@test "_lsof_first_name keeps a path containing spaces intact" {
  run bash -c 'source "$1"; printf "%s\n" "$2" | _lsof_first_name' _ "$LIB" "n$BUNDLED"
  [ "$status" -eq 0 ]
  [ "$output" = "$BUNDLED" ]
}

@test "_lsof_first_name takes the first name and ignores other field types" {
  run bash -c 'source "$1"; printf "p123\nftxt\n%s\nn/second/path\n" "$2" | _lsof_first_name' \
    _ "$LIB" "n$BARE"
  [ "$status" -eq 0 ]
  [ "$output" = "$BARE" ]
}

@test "_lsof_first_name yields nothing when lsof returned no name" {
  run bash -c 'source "$1"; printf "p123\n" | _lsof_first_name' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── resolve_claude_exe ─────────────────────────────────────────────────────────

# A pid with no process behind it, not the current one: this suite is itself run
# from a claude process most of the time, so walking up from $$ resolves a real
# executable and asserting emptiness there passes only off a developer's machine.
@test "resolve_claude_exe yields nothing when the walk finds no process" {
  run bash -c 'source "$1"; resolve_claude_exe 999999' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
