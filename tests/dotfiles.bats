#!/usr/bin/env bats

load helpers/setup

@test "dotfiles --help lists the new subcommands" {
  run "$DOTFILES_BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"push"* ]]
  [[ "$output" == *"freeze"* ]]
  [[ "$output" == *"status"* ]]
}

@test "dotfiles push exits 0 when not implemented (stub)" {
  run "$DOTFILES_BIN" push --dry-run
  [ "$status" -eq 0 ]
}

@test "dotfiles status exits 0 when not implemented (stub)" {
  run "$DOTFILES_BIN" status
  [ "$status" -eq 0 ]
}
