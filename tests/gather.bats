#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

GATHER="$DOTFILES_ROOT/agents/skills/git-conventions/scripts/gather.sh"

# suggest-commit ran this command inline at 9486a3e. It is the oracle for
# gather.sh under default config. Never edit it to match the script: a copy of
# gather.sh's command here agrees with whatever the script does.
old_gather() {
  git status --porcelain && git diff HEAD --stat && git diff HEAD -U1 -- ':(exclude)*.lock' ':(exclude)*-lock.json'
}

# with_config <name=value> <command>...: runs <command> with one setting given
# through the environment, which outranks every config file.
with_config() {
  local setting=$1
  shift
  GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0="${setting%%=*}" GIT_CONFIG_VALUE_0="${setting#*=}" "$@"
}

# new_fixture: a repo, cd'd into, holding every kind of change the gather
# reports: a modified tracked file, a staged new file, an untracked file,
# modified lockfiles at the root and in sub/, and a submodule commit in emb/.
# Under $BATS_TEST_TMPDIR, never the dotfiles working tree.
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
  # The fixture reaches each part of the output.
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
  # The control: without top magic the exclusion binds to sub/, and the root
  # lockfile's patch comes through.
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
    # The control: each setting changes what the old command prints.
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
  # info/attributes, not .gitattributes, so the fixture's status is unchanged.
  printf 'tracked.txt diff=upper\n' > .git/info/attributes
  # The control: the driver rewrites the old command's patch.
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

# The other cases run the script under PATH's bash, as a skill's `bash <path>`
# call does. AGENTS.md also requires /bin/bash 3.2, which is /bin/bash on macOS.
@test "the script answers identically under /bin/bash and PATH's bash" {
  new_fixture
  assert_script_portable : "$GATHER"
  printf '%s\n' "$output" | grep -Fx 'A  staged.txt' > /dev/null || fail "unexpected output: $output"
}

# One copy of the command, rather than a test pinning two copies together. The
# scan's `*-lock.json` also matches the pathspec without `top`, the form a copy
# of the old command would carry.
@test "exactly one file under agents/skills/ holds the gather's lockfile pathspec" {
  local hits
  grep -F -e "':(top,exclude)*-lock.json'" "$GATHER" > /dev/null \
    || fail "gather.sh no longer holds the pathspec, so the scan below matches nothing"
  hits="$(grep -rlF -e '*-lock.json' "$DOTFILES_ROOT/agents/skills" || true)"
  [ "$hits" = "$GATHER" ] \
    || fail "$(printf 'expected the pathspec in gather.sh alone, found it in:\n%s' "${hits//$DOTFILES_ROOT\//}")"
}
