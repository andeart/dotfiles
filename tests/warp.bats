#!/usr/bin/env bats

load helpers/setup

WARP_BIN="$DOTFILES_ROOT/bin/warp"

# Every test below uses --print or an error path, so `open` is never reached —
# no real Warp tabs are spawned, and the suite runs on non-macOS CI.

@test "warp --print encodes an absolute path's slashes as %2F" {
  tmp="$(mktemp -d)"
  run "$WARP_BIN" --print "$tmp"
  [ "$status" -eq 0 ]
  [[ "$output" == "warp://action/new_tab?path="* ]]
  encoded="${output#warp://action/new_tab?path=}"
  [[ "$encoded" == *"%2F"* ]]
  [[ "$encoded" != *"/"* ]]
}

@test "warp --print resolves '.' to the current directory" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/sub"
  cd "$tmp/sub"
  run "$WARP_BIN" --print .
  [ "$status" -eq 0 ]
  encoded="${output#warp://action/new_tab?path=}"
  [[ "$encoded" == *"%2Fsub" ]]
}

@test "warp --print resolves a relative path against \$PWD" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/child"
  cd "$tmp"
  run "$WARP_BIN" --print child
  [ "$status" -eq 0 ]
  encoded="${output#warp://action/new_tab?path=}"
  [[ "$encoded" == *"%2Fchild" ]]
}

@test "warp --print encodes spaces in the path as %20" {
  tmp="$(mktemp -d)"
  mkdir "$tmp/with space"
  run "$WARP_BIN" --print "$tmp/with space"
  [ "$status" -eq 0 ]
  encoded="${output#warp://action/new_tab?path=}"
  [[ "$encoded" == *"%20"* ]]
}

@test "warp with no arguments prints usage and exits 1" {
  run "$WARP_BIN"
  [ "$status" -eq 1 ]
  [[ "$output" == *"usage: warp"* ]]
}

@test "warp with extra arguments exits 1" {
  tmp="$(mktemp -d)"
  run "$WARP_BIN" "$tmp" "$tmp"
  [ "$status" -eq 1 ]
  [[ "$output" == *"unexpected argument"* ]]
}

@test "warp on a nonexistent path exits 1" {
  run "$WARP_BIN" --print "/no/such/dir/anywhere"
  [ "$status" -eq 1 ]
  [[ "$output" == *"no such file or directory"* ]]
}

@test "warp on a regular file exits 1" {
  tmp="$(mktemp -d)"
  touch "$tmp/afile"
  run "$WARP_BIN" --print "$tmp/afile"
  [ "$status" -eq 1 ]
  [[ "$output" == *"not a directory"* ]]
}
