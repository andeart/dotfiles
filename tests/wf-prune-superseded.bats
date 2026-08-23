#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

PROBE="$DOTFILES_ROOT/agents/skills/wf-prune/scripts/superseded-probe.sh"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
call() {
  run bash -c '_WF_PRUNE_LIB_ONLY=1 source "$0"; "$@"' "$PROBE" "$@"
}

# ─── identifier extraction ─────────────────────────────────────────────────

@test "identifier: reads a work item id off the front of a branch name" {
  call wf_identifier_from_branch dx-56-skill-trigger-evals
  [ "$status" -eq 0 ]
  [ "$output" = "DX-56" ]
}

@test "identifier: strips the worktree- prefix EnterWorktree adds" {
  call wf_identifier_from_branch worktree-pf-62-onboarding-state-picker
  [ "$output" = "PF-62" ]
}

@test "identifier: a bare slug yields nothing" {
  call wf_identifier_from_branch deepen-studio-site
  [ -z "$output" ]
}

@test "identifier: a leading number is not an identifier" {
  call wf_identifier_from_branch 12-create-add-task-ui
  [ -z "$output" ]
}

@test "identifier: a single word yields nothing" {
  call wf_identifier_from_branch temp
  [ -z "$output" ]
}

# Matches wf-wrap's rule, which anchors at the start of the name. A `user/`
# prefix therefore reads as no identifier, so the tier never fires on branches
# named that way - see the gap noted in SKILL.md.
@test "identifier: a user-prefixed branch yields nothing" {
  call wf_identifier_from_branch anurag/bya-174-show-indicators
  [ -z "$output" ]
}

@test "identifier: a slug that merely contains a number is not an identifier" {
  call wf_identifier_from_branch temp/Y2-3-exploration
  [ -z "$output" ]
}

# ─── fixture: supersede-and-redo ───────────────────────────────────────────

# Builds a repo in the shape DX-61 is about:
#   main          base -> landed   (the work, redone and squash-merged under a
#                                   different branch name)
#   dx-9-feature  base -> draft    (abandoned before review, never pushed)
# The draft and the landed commit touch the same paths, and the draft holds the
# older content of each. Exports $LANDED for the gh stub to hand back.
supersede_repo() {
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root"
  cd "$root" || return 1
  git init -q
  git branch -M main

  printf 'v1\n' > shared.txt
  git add -A && git commit -q -m base

  git switch -q -c dx-9-feature
  printf 'draft\n' > shared.txt
  printf 'draft\n' > added.txt
  git add -A && git commit -q -m 'draft of the feature'

  git switch -q main
  printf 'final\n' > shared.txt
  printf 'final\n' > added.txt
  git add -A && git commit -q -m 'DX-9: Add the feature (#7)'
  export LANDED
  LANDED=$(git rev-parse HEAD)
}

# A gh stub reporting one merged PR #7 titled "DX-9: ..." whose merge commit is
# $LANDED and whose changed files are $PR_FILES_JSON. Defined as shell source so
# each test can drop it into the sourced subshell.
GH_STUB='gh() {
  case "$*" in
    *"pr list"*)  printf "%s" "$PR_LIST_JSON" ;;
    *"pr view"*)  printf "%s" "$PR_FILES_JSON" ;;
  esac
}'

# pr_merged <number> <title> <merge-commit>: one merged PR for the stub to report.
pr_merged() {
  export PR_LIST_JSON="[{\"number\":$1,\"title\":\"$2\",\"mergeCommit\":{\"oid\":\"$3\"}}]"
}

# pr_none: no merged PR carries the identifier.
pr_none() { export PR_LIST_JSON='[]'; }

# pr_files <path>...: declare which paths the merged PR touched.
pr_files() {
  local json="" p
  for p in "$@"; do json="$json{\"path\":\"$p\"},"; done
  export PR_FILES_JSON="{\"files\":[${json%,}]}"
}

probe() {
  run bash -c "_WF_PRUNE_LIB_ONLY=1 source \"\$1\"; $GH_STUB
    wf_probe_branch \"\$2\" \"\$3\"" _ "$PROBE" "$1" "$2"
}

# ─── the case DX-61 is about ───────────────────────────────────────────────

@test "probe: flags a branch whose work landed under a different branch name" {
  supersede_repo
  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt added.txt
  probe dx-9-feature main
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=superseded"* ]]
}

# ─── branches that must stay excluded ──────────────────────────────────────

# The branch's only work is a deletion, and the default branch still has the
# file. Path coverage alone cannot see this: the path is in the PR's file list,
# so it reads as covered while the deletion never landed.
@test "probe: excludes a branch whose deletion never landed" {
  local root="$BATS_TEST_TMPDIR/repo"
  mkdir -p "$root"
  cd "$root" || return 1
  git init -q
  git branch -M main
  printf 'v1\n' > shared.txt
  printf 'v1\n' > doomed.txt
  git add -A && git commit -q -m base

  # Built with plumbing, and the branch is never checked out: the fixture needs
  # a commit that drops a path, without a remove verb and without leaving the
  # file untracked in the working tree.
  local base tree commit
  base=$(git rev-parse HEAD)
  git update-index --force-remove doomed.txt
  tree=$(git write-tree)
  commit=$(git commit-tree "$tree" -p "$base" -m 'drop the doomed file')
  git branch dx-9-feature "$commit"
  git read-tree --reset -u HEAD

  git switch -q main
  printf 'final\n' > shared.txt
  printf 'final\n' > doomed.txt
  git add -A && git commit -q -m 'DX-9: Add the feature (#7)'
  export LANDED
  LANDED=$(git rev-parse HEAD)

  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt doomed.txt
  probe dx-9-feature main
  [ "$status" -eq 1 ]
  [[ "$output" == *"verdict=excluded"* ]]
}

@test "probe: excludes a branch holding a file the default branch never got" {
  supersede_repo
  cd "$BATS_TEST_TMPDIR/repo" || return 1
  git switch -q dx-9-feature
  printf 'only here\n' > novel.txt
  git add -A && git commit -q -m 'work that never landed'
  git switch -q main

  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt added.txt
  probe dx-9-feature main
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=uncovered-paths"* ]]
}

@test "probe: excludes a branch whose work item has no merged pull request" {
  supersede_repo
  pr_none
  pr_files shared.txt added.txt
  probe dx-9-feature main
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=no-landed-pr"* ]]
}

@test "probe: excludes a branch whose name carries no work item identifier" {
  supersede_repo
  cd "$BATS_TEST_TMPDIR/repo" || return 1
  git branch -q no-identifier dx-9-feature

  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt added.txt
  probe no-identifier main
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=no-identifier"* ]]
}

# A pull request that landed at or before the branch's merge base cannot be
# where the branch's work went, so it must not count toward coverage.
@test "probe: ignores a pull request that landed before the branch diverged" {
  supersede_repo
  cd "$BATS_TEST_TMPDIR/repo" || return 1
  local mb
  mb=$(git merge-base main dx-9-feature)

  pr_merged 7 "DX-9: Add the feature" "$mb"
  pr_files shared.txt added.txt
  probe dx-9-feature main
  [ "$status" -eq 1 ]
  [[ "$output" == *"reason=no-landed-pr"* ]]
}

@test "probe: names the identifier and pull requests behind a superseded verdict" {
  supersede_repo
  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt added.txt
  probe dx-9-feature main
  [ "$status" -eq 0 ]
  [[ "$output" == *"identifier=DX-9"* ]]
  [[ "$output" == *"prs=7"* ]]
  [[ "$output" == *"paths=2"* ]]
}

# ─── command line ──────────────────────────────────────────────────────────

@test "cli: --help prints usage and exits 0" {
  run bash "$PROBE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: superseded-probe.sh"* ]]
}

@test "cli: reports the verdict for a branch given on the command line" {
  supersede_repo
  pr_merged 7 "DX-9: Add the feature" "$LANDED"
  pr_files shared.txt added.txt
  run bash -c "$GH_STUB
    export -f gh
    bash \"\$1\" dx-9-feature main" _ "$PROBE"
  [ "$status" -eq 0 ]
  [[ "$output" == *"verdict=superseded"* ]]
}

@test "cli: exits 2 when the arguments are missing" {
  run bash "$PROBE"
  [ "$status" -eq 2 ]
}
