#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

BIN="$DOTFILES_ROOT/bin/gh-set-default-settings"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_GH_SETTINGS_LIB_ONLY=1 source "$0"; "$@"' "$BIN" "$@"
}

# ─── flags & help ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: gh-set-default-settings"* ]]
}

@test "an unknown flag exits non-zero" {
  run "$BIN" --nope
  [ "$status" -ne 0 ]
}

@test "no repo argument exits non-zero" {
  run "$BIN"
  [ "$status" -ne 0 ]
}

# ─── parse_repo (pure) ─────────────────────────────────────────────────────

@test "parse_repo normalizes the git@ scp form" {
  call parse_repo "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "parse_repo normalizes the https form" {
  call parse_repo "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "parse_repo passes through the owner/repo form" {
  call parse_repo "owner/repo"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}
