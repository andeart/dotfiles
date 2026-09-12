#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# wf-wrap and wf-prune substitute a local branch name into commands, several of
# them unquoted, so each first routes the name through a `case` allowlist. That
# line lives in a SKILL.md block rather than a script, so it is read out of the
# skill and run under every shell a SKILL.md block runs in.

# Names a substituted command would run or misread. All but `-x` are names git
# accepts for a branch, which the first case re-checks; `-x` stays because git
# reads an argument beginning with `-` as an option.
HOSTILE=( 'a;touch${IFS}pwned' 'a$(touch${IFS}pwned)' 'a`touch${IFS}pwned`' 'a|sh' 'a&b' 'a>pwned' "a'b" 'a"b' '-x' )

# Names the allowlist has to let through, or the skills refuse ordinary work.
ORDINARY=( 'DX-98-skill-block' 'feature/foo.bar' 'worktree-zzz-0' 'user/abc_1' )

# block_shells: /bin/bash, PATH's bash, /bin/zsh and PATH's zsh, resolved and
# deduplicated, skipping any this machine lacks.
block_shells() {
  local sh path seen=" "
  for sh in /bin/bash bash /bin/zsh zsh; do
    path="$(command -v "$sh" 2>/dev/null)" || continue
    [ -n "$path" ] || continue
    case "$seen" in *" $path "*) continue ;; esac
    seen="$seen$path "
    printf '%s\n' "$path"
  done
}

# check_line <skill> <marker>: sets LINE to the one line of the skill's SKILL.md
# holding <marker>, failing unless exactly one does.
check_line() {
  local file="$DOTFILES_ROOT/agents/skills/$1/SKILL.md" count
  count="$(grep -c -F -e "$2" "$file" || true)"
  [ "$count" = 1 ] || fail "expected one line holding $2 in $file, found $count"
  LINE="$(grep -F -e "$2" "$file")"
}

# route <var> <name>: runs LINE with <var> bound to <name> under every shell,
# from an empty directory, leaving the output in ROUTED. Fails when a shell
# errors, when two shells disagree, or when part of the name ran. zsh gets -f
# so the caller's startup files add nothing; bash -c reads none.
route() {
  local var=$1 name=$2 sh opt out ran=0 dir="$BATS_TEST_TMPDIR/route"
  mkdir -p "$dir"
  ROUTED=
  while IFS= read -r sh; do
    case "$sh" in *zsh) opt=-f ;; *) opt=+f ;; esac
    out="$(cd "$dir" && NAME="$name" "$sh" "$opt" -c "$var=\$NAME; $LINE")" \
      || fail "$sh failed routing: $name"
    if [ "$ran" -eq 0 ]; then
      ROUTED=$out
    else
      [ "$out" = "$ROUTED" ] || fail "$sh routed $name as $out, the first shell as $ROUTED"
    fi
    ran=$((ran + 1))
  done < <(block_shells)
  [ "$ran" -ge 1 ] || fail "no shell available to run the check"
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
