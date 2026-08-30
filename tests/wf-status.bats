#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

WF_STATUS="$DOTFILES_ROOT/bin/wf-status"

# Source in library mode inside a subshell so its `set -euo pipefail` is
# contained, then invoke one function.
call() {
  run bash -c '_WF_STATUS_LIB_ONLY=1 source "$0"; "$@"' "$WF_STATUS" "$@"
}

# fixture <name>: a git repo with one commit, printed as its path. No remote, so
# nothing in these tests can reach the network.
fixture() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  git -C "$root" init -q -b main .
  git -C "$root" commit -q --allow-empty -m "init"
  printf '%s\n' "$root"
}

@test "--help prints usage and exits 0" {
  run bash "$WF_STATUS" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: wf-status"* ]]
}

@test "an unknown flag exits 2" {
  run bash "$WF_STATUS" --nope
  [ "$status" -eq 2 ]
}

@test "a path that is not a git repository exits 2 and names it" {
  local d="$BATS_TEST_TMPDIR/plain"; mkdir -p "$d"
  run --separate-stderr bash "$WF_STATUS" "$d"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"$d"* ]]
}

# The identifier rule is wf-wrap's, and EnterWorktree's branches are the reason
# for the strip: without it they match nothing at all.
@test "identifier_of strips a leading worktree- prefix" {
  call identifier_of "worktree-dx-57-wf-status"
  [ "$status" -eq 0 ]
  [ "$output" = "DX-57" ]
}

@test "identifier_of reads a bare identifier branch" {
  call identifier_of "dx-57-wf-status"
  [ "$status" -eq 0 ]
  [ "$output" = "DX-57" ]
}

@test "identifier_of uppercases the project prefix" {
  call identifier_of "pf-192-member-profile-read"
  [ "$status" -eq 0 ]
  [ "$output" = "PF-192" ]
}

@test "identifier_of prints a dash for a branch carrying none" {
  call identifier_of "fix-readme"
  [ "$status" -eq 0 ]
  [ "$output" = "-" ]
}

# A branch named only worktree-<words> has no identifier once stripped.
@test "identifier_of prints a dash when only the prefix looks like one" {
  call identifier_of "worktree-fix-readme"
  [ "$status" -eq 0 ]
  [ "$output" = "-" ]
}

@test "a repo with no linked worktrees reports the main tree only" {
  local root; root="$(fixture solo)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
}

@test "porcelain rows carry seven tab-separated fields" {
  local root; root="$(fixture fields)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '{print NF}' | sort -u)" = "7" ]
}

@test "a linked worktree gets its own row" {
  local root; root="$(fixture linked)"
  git -C "$root" worktree add -q -b dx-99-thing "$BATS_TEST_TMPDIR/linked-wt"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  [[ "$output" == *"DX-99"* ]]
}

@test "a dirty worktree reports its file count" {
  local root; root="$(fixture dirty)"
  : > "$root/untracked.txt"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '{print $5}')" = "1" ]
}

# No remote in these fixtures, so the gh lookup must degrade rather than hang or
# error. This is the property that lets the script run in a fresh clone.
@test "a repo with no remote reports pr_state none" {
  local root; root="$(fixture noremote)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '{print $6}')" = "none" ]
}

@test "several repo paths are all reported" {
  local a b; a="$(fixture multi-a)"; b="$(fixture multi-b)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$a" "$b"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
}

# A bad repo-path argument must not discard rows already collected from
# earlier, valid ones - the same failure-isolation property a prunable
# worktree already holds one level down, applied one level up. Partial
# sweeps exit 1 so a caller can tell "some paths were unreadable" apart
# from "every path resolved."
@test "a valid path followed by an invalid one prints the valid row and exits 1" {
  local good; good="$(fixture good)"
  local bad="$BATS_TEST_TMPDIR/nonexistent"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$good" "$bad"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  [[ "$stderr" == *"$bad"* ]]
}

@test "an invalid path followed by a valid one still prints the valid row" {
  local bad="$BATS_TEST_TMPDIR/nonexistent"
  local good; good="$(fixture good)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$bad" "$good"
  [ "$status" -eq 1 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 1 ]
  [[ "$stderr" == *"$bad"* ]]
}

@test "every repo path invalid exits 2 with no output" {
  local bad1="$BATS_TEST_TMPDIR/nope1" bad2="$BATS_TEST_TMPDIR/nope2"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$bad1" "$bad2"
  [ "$status" -eq 2 ]
  [ -z "$output" ]
  [[ "$stderr" == *"$bad1"* ]]
  [[ "$stderr" == *"$bad2"* ]]
}

@test "several valid repo paths still exit 0" {
  local a b; a="$(fixture allgood-a)"; b="$(fixture allgood-b)"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$a" "$b"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

# A worktree directory moved or deleted without `git worktree prune` is a
# state git itself names (a `prunable` line in --porcelain output), not a
# hypothetical. It must cost only its own row's detail, not the run: the main
# tree's row - already collected - must still come out, and the exit must
# stay 0.
@test "a prunable worktree reports rather than aborting the run" {
  local root; root="$(fixture prunable)"
  git -C "$root" worktree add -q -b dx-30-gone "$BATS_TEST_TMPDIR/prunable-wt"
  mv "$BATS_TEST_TMPDIR/prunable-wt" "$BATS_TEST_TMPDIR/prunable-wt-moved"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  [[ "$output" == *"DX-30"* ]]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$3 == "dx-30-gone" {print $5}')" = "prunable" ]
}
