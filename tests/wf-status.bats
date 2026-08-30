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

# A detached worktree carries no branch. gh treats `pr view ""` as `pr view`
# with no argument at all - it falls back to the current branch of whatever
# repo it runs in - so a row with no branch must never reach gh, or it reports
# a real but unrelated PR.
@test "a detached worktree reports no branch, no identifier and no PR" {
  local root; root="$(fixture detached)"
  git -C "$root" worktree add -q --detach "$BATS_TEST_TMPDIR/detached-wt"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  # repo equals worktree only on the main tree, so $1 != $2 selects the linked
  # row without depending on how the tmpdir path resolves.
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $3}')" = "-" ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $4}')" = "-" ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $6}')" = "none" ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $7}')" = "-" ]
}

# Binds the short-circuit where it matters: not that the row says none, but
# that gh was never consulted for it. A gh that answers would answer about
# some other branch entirely.
@test "a detached worktree is never looked up in gh" {
  local root; root="$(fixture nolookup)"
  git -C "$root" worktree add -q --detach "$BATS_TEST_TMPDIR/nolookup-wt"
  export CALLS="$BATS_TEST_TMPDIR/gh-calls"
  : > "$CALLS"
  run bash -c '
    _WF_STATUS_LIB_ONLY=1 source "$1"
    gh() { printf "%s\n" "$3" >> "$CALLS"; return 1; }
    collect_rows "$2"
  ' _ "$WF_STATUS" "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$CALLS" | tr -d ' ')" -eq 1 ]
  [ "$(cat "$CALLS")" = "main" ]
}

# git reports a worktree that is both detached and prunable with no branch line
# at all, so the field that can be empty and the field that must survive are in
# the same row. Nothing may shift into the gap: dirty must still read prunable.
@test "a worktree that is both detached and prunable still reports prunable" {
  local root; root="$(fixture detached-prunable)"
  git -C "$root" worktree add -q --detach "$BATS_TEST_TMPDIR/dp-wt"
  mv "$BATS_TEST_TMPDIR/dp-wt" "$BATS_TEST_TMPDIR/dp-wt-moved"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $3}')" = "-" ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $5}')" = "prunable" ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '$1 != $2 {print $6}')" = "none" ]
}

# repo is the repository's main worktree path whichever worktree the row
# describes - and whichever worktree the argument named. Passing a linked
# worktree is the only way to tell that apart from "the path we were given".
@test "a linked worktree given as the argument still reports the main worktree as repo" {
  local root; root="$(fixture arg-linked)"
  local main_path; main_path="$(cd "$root" && pwd -P)"
  git -C "$root" worktree add -q -b dx-88-arg "$BATS_TEST_TMPDIR/arg-linked-wt"
  run --separate-stderr bash "$WF_STATUS" --porcelain "$BATS_TEST_TMPDIR/arg-linked-wt"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | grep -c .)" -eq 2 ]
  [ "$(printf '%s\n' "$output" | awk -F'\t' '{print $1}' | sort -u)" = "$main_path" ]
}

# The aligned table is column -t over the porcelain rows, and column -t
# collapses an empty field, shifting every column after it. Every row must
# still carry seven whitespace-separated cells.
@test "the aligned table keeps its columns on a detached worktree" {
  local root; root="$(fixture table-detached)"
  git -C "$root" worktree add -q --detach "$BATS_TEST_TMPDIR/table-detached-wt"
  run --separate-stderr bash "$WF_STATUS" "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk '{print NF}' | sort -u)" = "7" ]
}

# lookup_with_gh <state> <isDraft> <url> [branch]: pr_lookup with gh stubbed to
# a canned `--json state,isDraft,url` response, so the state mapping is
# exercised with no network call and no PR to point at.
lookup_with_gh() {
  export STUB_TSV
  STUB_TSV="$(printf '%s\t%s\t%s' "$1" "$2" "$3")"
  run bash -c '
    _WF_STATUS_LIB_ONLY=1 source "$1"
    gh() { printf "%s\n" "$STUB_TSV"; }
    pr_lookup "$2" "$3"
  ' _ "$WF_STATUS" "$BATS_TEST_TMPDIR" "${4-dx-1-thing}"
}

# pr_field <n>: field n of the tab-separated pr_lookup output `run` captured.
pr_field() {
  printf '%s\n' "$output" | cut -f"$1"
}

@test "pr_lookup maps a merged PR to merged" {
  lookup_with_gh MERGED false https://example.com/pull/9
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "merged" ]
  [ "$(pr_field 2)" = "https://example.com/pull/9" ]
}

@test "pr_lookup maps a closed PR to closed" {
  lookup_with_gh CLOSED false https://example.com/pull/9
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "closed" ]
  [ "$(pr_field 2)" = "https://example.com/pull/9" ]
}

@test "pr_lookup maps an open draft PR to draft" {
  lookup_with_gh OPEN true https://example.com/pull/9
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "draft" ]
  [ "$(pr_field 2)" = "https://example.com/pull/9" ]
}

@test "pr_lookup maps an open non-draft PR to ready" {
  lookup_with_gh OPEN false https://example.com/pull/9
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "ready" ]
  [ "$(pr_field 2)" = "https://example.com/pull/9" ]
}

# A state gh may grow later must degrade to none rather than be reported under
# one of the five documented values.
@test "pr_lookup reports none for a state it does not know" {
  lookup_with_gh QUEUED false https://example.com/pull/9
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "none" ]
  [ "$(pr_field 2)" = "-" ]
}

@test "pr_lookup reports none when gh answers with nothing" {
  run bash -c '
    _WF_STATUS_LIB_ONLY=1 source "$1"
    gh() { printf ""; }
    pr_lookup "$2" dx-1-thing
  ' _ "$WF_STATUS" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "none" ]
  [ "$(pr_field 2)" = "-" ]
}

# The unit-level half of the detached-worktree case: even with a gh that would
# answer, an empty branch reports no PR and asks nothing.
@test "pr_lookup reports none for an empty branch without calling gh" {
  export CALLS="$BATS_TEST_TMPDIR/gh-calls"
  : > "$CALLS"
  run bash -c '
    _WF_STATUS_LIB_ONLY=1 source "$1"
    gh() { printf "called\n" >> "$CALLS"; printf "OPEN\tfalse\thttps://example.com/pull/9\n"; }
    pr_lookup "$2" ""
  ' _ "$WF_STATUS" "$BATS_TEST_TMPDIR"
  [ "$status" -eq 0 ]
  [ "$(pr_field 1)" = "none" ]
  [ "$(pr_field 2)" = "-" ]
  [ ! -s "$CALLS" ]
}
