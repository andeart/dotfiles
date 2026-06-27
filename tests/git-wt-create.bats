#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

WT_CREATE_BIN="$DOTFILES_ROOT/git/bin/git-wt-create"

# Build a fresh repo with a bare "origin" for each test. Sets:
#   $REPO_PARENT — tmp root holding the bare remote, the clone, and $WT
#   $REPO        — the clone (cwd for the test body); its dir name is "repo-a",
#                  which is what the repo-name prefix is derived from
#   $WT          — a pre-created worktrees directory
# Branch fixtures: "main" (default), "local-only" (local, no worktree),
# "only-remote" (exists on origin but not locally).
setup() {
  # Scrub git's repo-local env vars. Under the pre-commit hook, git exports
  # GIT_INDEX_FILE=.git/index (and friends), which would leak into the temp
  # repos below and break `git worktree add`. Harmless when run standalone.
  unset $(git rev-parse --local-env-vars)

  REPO_PARENT="$(mktemp -d)"
  REMOTE="$REPO_PARENT/remote.git"
  REPO="$REPO_PARENT/repo-a"
  WT="$REPO_PARENT/wts"

  git init -q --bare "$REMOTE"
  git clone -q "$REMOTE" "$REPO" 2>/dev/null
  cd "$REPO"
  git config user.email t@t.t
  git config user.name t
  git config commit.gpgsign false

  git commit -q --allow-empty -m init
  git branch -M main
  git push -q -u origin main

  # A branch that exists on origin but not locally.
  git switch -q -c only-remote
  git commit -q --allow-empty -m remote
  git push -q -u origin only-remote
  git switch -q main
  git branch -q -D only-remote

  # A purely local branch with no worktree yet.
  git branch local-only main

  mkdir -p "$WT"
}

# ─── happy paths ───────────────────────────────────────────────────────────────

@test "new branch (-c) creates a repo-prefixed worktree and prints only the path" {
  run --separate-stderr "$WT_CREATE_BIN" -p "$WT" -b feature-x -c --base main
  [ "$status" -eq 0 ]
  [ "$output" = "$WT/repo-a-feature-x" ]
  [ "${#lines[@]}" -eq 1 ]
  [ -d "$WT/repo-a-feature-x" ]
  [[ "$stderr" == *"is ready"* ]]
}

@test "the worktree directory is prefixed with the repo name" {
  run "$WT_CREATE_BIN" -p "$WT" -b new-branch -c --base main
  [ "$status" -eq 0 ]
  [ -d "$WT/repo-a-new-branch" ]
}

@test "an existing local branch is checked out into a worktree" {
  run --separate-stderr "$WT_CREATE_BIN" -p "$WT" -b local-only
  [ "$status" -eq 0 ]
  [ "$output" = "$WT/repo-a-local-only" ]
  [ -d "$WT/repo-a-local-only" ]
}

@test "a remote-only branch creates a worktree tracking origin" {
  run --separate-stderr "$WT_CREATE_BIN" -p "$WT" -b only-remote
  [ "$status" -eq 0 ]
  [ "$output" = "$WT/repo-a-only-remote" ]
  upstream="$(git -C "$WT/repo-a-only-remote" rev-parse --abbrev-ref --symbolic-full-name '@{upstream}')"
  [ "$upstream" = "origin/only-remote" ]
}

@test "stdout carries exactly one line, the bare worktree path" {
  run --separate-stderr "$WT_CREATE_BIN" -p "$WT" -b solo -c --base main
  [ "$status" -eq 0 ]
  [ "${#lines[@]}" -eq 1 ]
  [ "${lines[0]}" = "$WT/repo-a-solo" ]
}

# ─── branch resolution errors ──────────────────────────────────────────────────

@test "a branch that exists neither locally nor on remote errors" {
  run "$WT_CREATE_BIN" -p "$WT" -b ghost
  [ "$status" -ne 0 ]
  [[ "$output" == *"does not exist locally or on remote"* ]]
}

@test "-c rejects a branch that already exists locally" {
  run "$WT_CREATE_BIN" -p "$WT" -b local-only -c --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists as a branch or tag"* ]]
}

@test "-c rejects a branch that already exists on remote" {
  run "$WT_CREATE_BIN" -p "$WT" -b only-remote -c --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists on remote"* ]]
}

@test "-c errors when the base branch does not exist" {
  run "$WT_CREATE_BIN" -p "$WT" -b brand-new -c --base nope
  [ "$status" -ne 0 ]
  [[ "$output" == *"base branch 'nope' does not exist"* ]]
}

# ─── flag validation ───────────────────────────────────────────────────────────

@test "-c requires --base" {
  run "$WT_CREATE_BIN" -p "$WT" -b brand-new -c
  [ "$status" -ne 0 ]
  [[ "$output" == *"--base <base> is required with -c"* ]]
}

@test "--base is rejected without -c" {
  run "$WT_CREATE_BIN" -p "$WT" -b local-only --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"--base is only valid with -c"* ]]
}

@test "-p is required" {
  run "$WT_CREATE_BIN" -b local-only
  [ "$status" -ne 0 ]
  [[ "$output" == *"-p <worktrees-dir> is required"* ]]
}

@test "-b is required" {
  run "$WT_CREATE_BIN" -p "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"-b <branch> is required"* ]]
}

@test "-i cannot be combined with the other flags" {
  run "$WT_CREATE_BIN" -i -p "$WT"
  [ "$status" -ne 0 ]
  [[ "$output" == *"cannot be combined"* ]]
}

@test "an unknown argument errors" {
  run "$WT_CREATE_BIN" --bogus
  [ "$status" -ne 0 ]
  [[ "$output" == *"unknown argument"* ]]
}

# ─── path + directory guards ───────────────────────────────────────────────────

@test "an already-existing worktree path errors" {
  mkdir -p "$WT/repo-a-feature-x"
  run "$WT_CREATE_BIN" -p "$WT" -b feature-x -c --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"already exists"* ]]
}

@test "a missing worktrees dir is created when the prompt is accepted" {
  newdir="$REPO_PARENT/fresh-wts"
  run bash -c "echo y | '$WT_CREATE_BIN' -p '$newdir' -b made -c --base main"
  [ "$status" -eq 0 ]
  [ -d "$newdir/repo-a-made" ]
}

@test "a missing worktrees dir is left alone when the prompt is declined" {
  newdir="$REPO_PARENT/declined-wts"
  run bash -c "echo n | '$WT_CREATE_BIN' -p '$newdir' -b made -c --base main"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Aborted"* ]]
  [ ! -d "$newdir" ]
}

@test "a worktrees path that is a file (not a dir) errors" {
  touch "$REPO_PARENT/afile"
  run "$WT_CREATE_BIN" -p "$REPO_PARENT/afile" -b made -c --base main
  [ "$status" -ne 0 ]
  [[ "$output" == *"is not a directory"* ]]
}
