#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

GATHER="$DOTFILES_ROOT/agents/skills/git-conventions/scripts/gather.sh"

# old_gather: the inline gather command of suggest-commit at commit 9486a3e,
# with no flags. It is the reference output for gather.sh under default config.
# Do not change it to agree with the script: a copy of the command in gather.sh
# agrees with each change to the script.
old_gather() {
  git status --porcelain && git diff HEAD --stat && git diff HEAD -U1 -- ':(exclude)*.lock' ':(exclude)*-lock.json'
}

# with_config <name=value> <command>...: runs <command> with one setting in the
# environment. That setting has priority over all config files.
with_config() {
  local setting=$1
  shift
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="${setting%%=*}" GIT_CONFIG_VALUE_0="${setting#*=}" "$@"
}

# new_fixture: makes a repo and sets it as the cwd. The repo has each type of
# change that the gather reports: a changed tracked file, a staged new file, an
# untracked file, changed lockfiles at the root and in sub/, and a submodule
# commit in emb/. The repo is under $BATS_TEST_TMPDIR, never in the dotfiles
# working tree.
new_fixture() {
  local tmp
  tmp="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet .
  mkdir sub emb
  printf 'seed\n' > tracked.txt
  printf 'v1\n' > top.lock
  printf '{}\n' > package-lock.json
  printf 'v1\n' > sub/inner.lock
  printf 'seed\n' > sub/work.txt
  ( cd emb && git init --quiet . && printf 'e1\n' > f && git add f && git commit --quiet -m e1 )
  git add . 2>/dev/null
  git commit --quiet -m seed
  printf 'more\n' >> tracked.txt
  printf 'v2\n' > top.lock
  printf '{"v":2}\n' > package-lock.json
  printf 'v2\n' > sub/inner.lock
  printf 'more\n' >> sub/work.txt
  printf 'new\n' > staged.txt
  git add staged.txt
  printf 'new\n' > untracked.txt
  ( cd emb && seq 1 40 > f && git commit --quiet -am e2 )
}

@test "from the root under default config, the output is the old inline command's, byte for byte" {
  new_fixture
  local expected
  expected="$(old_gather)"
  # The fixture puts content in each part of the output.
  printf '%s\n' "$expected" | grep -Fx '?? untracked.txt' > /dev/null || fail "fixture: no untracked line"
  printf '%s\n' "$expected" | grep -Fx 'A  staged.txt' > /dev/null || fail "fixture: no staged line"
  printf '%s\n' "$expected" | grep -F ' top.lock ' > /dev/null || fail "fixture: no lockfile in the stat"
  printf '%s\n' "$expected" | grep -F 'Subproject commit' > /dev/null || fail "fixture: no submodule line"

  run --separate-stderr bash "$GATHER"
  [ "$status" -eq 0 ] || fail "exit $status: $stderr"
  [ "$output" = "$expected" ] || fail "$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$output"))"
}

@test "from a subdirectory, a root lockfile stays in the stat and out of the patch" {
  new_fixture
  cd sub || fail "cd sub failed"
  # The control: without `top`, the exclusion binds to sub/, and the patch
  # includes the root lockfile.
  old_gather | grep -F 'diff --git a/top.lock' > /dev/null \
    || fail "fixture: the old command kept top.lock out from sub/"

  run --separate-stderr bash "$GATHER"
  [ "$status" -eq 0 ] || fail "exit $status: $stderr"
  printf '%s\n' "$output" | grep -F ' top.lock ' > /dev/null || fail "top.lock is missing from the stat"
  ! printf '%s\n' "$output" | grep -F 'diff --git a/top.lock' > /dev/null || fail "top.lock's patch came through"
  ! printf '%s\n' "$output" | grep -F 'diff --git a/sub/inner.lock' > /dev/null || fail "sub/inner.lock's patch came through"
}

@test "where HEAD does not resolve, both diffs are of the index" {
  local tmp
  tmp="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet .
  printf 'a\n' > a.txt
  git add a.txt
  printf 'b\n' > b.txt

  run --separate-stderr bash "$GATHER"
  [ "$status" -eq 0 ] || fail "exit $status: $stderr"
  [ "$output" = "$(git status --porcelain && git diff --cached --stat && git diff --cached -U1)" ]
  printf '%s\n' "$output" | grep -Fx '+a' > /dev/null || fail "a.txt's patch is missing: $output"
}

@test "user config does not change the output" {
  new_fixture
  local expected setting
  expected="$(bash "$GATHER")"
  for setting in color.ui=always diff.external=/usr/bin/false diff.ignoreSubmodules=all diff.submodule=diff status.showUntrackedFiles=no; do
    # The control: each setting changes the output of old_gather.
    [ "$(with_config "$setting" old_gather 2>&1)" != "$(old_gather)" ] \
      || fail "fixture: $setting does not change the old command's output"
    run --separate-stderr with_config "$setting" bash "$GATHER"
    [ "$status" -eq 0 ] || fail "$setting: exit $status: $stderr"
    [ "$output" = "$expected" ] || fail "$setting changed the output"
  done
}

@test "a textconv driver does not rewrite the patch" {
  new_fixture
  local expected
  expected="$(bash "$GATHER")"
  # Use info/attributes, not .gitattributes, so the status of the fixture does
  # not change.
  printf 'tracked.txt diff=upper\n' > .git/info/attributes
  # The control: the driver changes the patch of old_gather.
  with_config 'diff.upper.textconv=tr a-z A-Z <' old_gather | grep -Fx '+MORE' > /dev/null \
    || fail "fixture: the textconv driver does not rewrite the old command's patch"

  run --separate-stderr with_config 'diff.upper.textconv=tr a-z A-Z <' bash "$GATHER"
  [ "$status" -eq 0 ] || fail "exit $status: $stderr"
  [ "$output" = "$expected" ] || fail "$(diff <(printf '%s\n' "$expected") <(printf '%s\n' "$output"))"
}

@test "under diff.relative, run from a subdirectory, the output is the root's" {
  new_fixture
  local expected
  expected="$(bash "$GATHER")"
  cd sub || fail "cd sub failed"
  [ "$(with_config diff.relative=true git diff HEAD --stat)" != "$(git diff HEAD --stat)" ] \
    || fail "fixture: diff.relative does not change the stat from sub/"

  run --separate-stderr with_config diff.relative=true bash "$GATHER"
  [ "$status" -eq 0 ] || fail "exit $status: $stderr"
  [ "$output" = "$expected" ]
}

@test "any argument is a usage error" {
  run bash "$GATHER" --cached
  [ "$status" -eq 2 ]
}

# All other cases run the script with the bash on PATH, as the `bash <path>`
# call of a skill does. AGENTS.md also requires /bin/bash 3.2, which is
# /bin/bash on macOS.
@test "the script answers identically under /bin/bash and PATH's bash" {
  new_fixture
  assert_script_portable : "$GATHER"
  printf '%s\n' "$output" | grep -Fx 'A  staged.txt' > /dev/null || fail "unexpected output: $output"
}

# The gather command has one copy, so no test compares two copies. The scan for
# `*-lock.json` also finds the pathspec without `top`, as old_gather has it.
@test "exactly one file under agents/skills/ holds the gather's lockfile pathspec" {
  local hits
  grep -F -e "':(top,exclude)*-lock.json'" "$GATHER" > /dev/null \
    || fail "gather.sh no longer holds the pathspec, so the scan below matches nothing"
  hits="$(grep -rlF -e '*-lock.json' "$DOTFILES_ROOT/agents/skills" || true)"
  [ "$hits" = "$GATHER" ] \
    || fail "$(printf 'expected the pathspec in gather.sh alone, found it in:\n%s' "${hits//$DOTFILES_ROOT\//}")"
}
