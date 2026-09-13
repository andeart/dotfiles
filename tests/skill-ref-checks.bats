#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# wf-wrap and wf-prune put a local branch name into commands, some without
# quotes, so each skill first sends the name through a `case` allowlist. That
# line is in a SKILL.md block, not a script, so the tests read it from the skill
# and run it under each shell that runs a SKILL.md block.

# Names that a command would run or read wrongly. git accepts each one as a
# branch name except `-x`, and the first case checks this. `-x` is here because
# git reads an argument that starts with `-` as an option. `a{b,c}` runs nothing:
# an unquoted `git branch -D` expands it into two other branch names. The
# `pwned` check cannot see that, so only the routing assertion tests it.
HOSTILE=( 'a;touch${IFS}pwned' 'a$(touch${IFS}pwned)' 'a`touch${IFS}pwned`' 'a|sh' 'a&b' 'a>pwned' "a'b" 'a"b' 'a{b,c}' '-x' )

# Names that the allowlist must pass, or the skills refuse ordinary branches.
ORDINARY=( 'DX-98-skill-block' 'feature/foo.bar' 'worktree-zzz-0' 'user/abc_1' )

# The shells that run a SKILL.md block, as AGENTS.md states.
BLOCK_SHELLS=(/bin/bash bash /bin/zsh zsh)

# check_line <skill> <marker>: sets LINE to the one line of the skill's SKILL.md
# that holds <marker>. Fails unless exactly one line holds it.
check_line() {
  local file="$DOTFILES_ROOT/agents/skills/$1/SKILL.md"
  assert_one_line "$file" "$2"
  LINE="$(grep -F -e "$2" "$file")"
}

# route <var> <name>: runs LINE with <var> set to <name> under each BLOCK_SHELLS
# shell, in an empty directory, and puts the output in ROUTED. Fails when a
# shell fails, when two shells disagree, when an installed shell did not run, or
# when part of the name ran. zsh gets -f, so startup files add nothing; bash -c
# reads none.
route() {
  local var=$1 name=$2 sh opt out ran= dir="$BATS_TEST_TMPDIR/route"
  mkdir -p "$dir"
  ROUTED=
  while IFS= read -r sh; do
    case "$sh" in *zsh) opt=-f ;; *) opt=+f ;; esac
    out="$(cd "$dir" && NAME="$name" "$sh" "$opt" -c "$var=\$NAME; $LINE")" \
      || fail "$sh failed routing: $name"
    if [ -z "$ran" ]; then
      ROUTED=$out
    else
      [ "$out" = "$ROUTED" ] || fail "$sh routed $name as $out, the first shell as $ROUTED"
    fi
    ran="$ran$sh"$'\n'
  done < <(shells_among "${BLOCK_SHELLS[@]}")
  [ -n "$ran" ] || fail "no shell available to run the check"
  assert_shells_covered "$ran" "${BLOCK_SHELLS[@]}"
  [ ! -e "$dir/pwned" ] || fail "routing ran part of the name as a command: $name"
}

@test "every hostile name not beginning with - is one git accepts as a branch" {
  local name
  for name in "${HOSTILE[@]}"; do
    case "$name" in -*) continue ;; esac
    git check-ref-format --branch "$name" > /dev/null \
      || fail "git refuses this name, so it grades nothing: $name"
  done
}

@test "wf-wrap's refcheck refuses every hostile name and passes ordinary ones" {
  check_line wf-wrap 'case "$branch" in'
  local name
  for name in "${HOSTILE[@]}"; do
    route branch "$name"
    [ "$ROUTED" = refcheck=unsafe ] || fail "wf-wrap passed a hostile name ($ROUTED): $name"
  done
  for name in "${ORDINARY[@]}"; do
    route branch "$name"
    [ "$ROUTED" = refcheck=ok ] || fail "wf-wrap refused an ordinary name ($ROUTED): $name"
  done
}

@test "wf-prune keys every hostile name unsafe= and ordinary ones branch=" {
  check_line wf-prune 'case "$b" in'
  local name
  for name in "${HOSTILE[@]}"; do
    route b "$name"
    [ "$ROUTED" = "unsafe=$name" ] || fail "wf-prune passed a hostile name ($ROUTED): $name"
  done
  for name in "${ORDINARY[@]}"; do
    route b "$name"
    [ "$ROUTED" = "branch=$name" ] || fail "wf-prune refused an ordinary name ($ROUTED): $name"
  done
}
