#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"
SCRIPT="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/find-working-notes.sh"
CALL="bash ~/.agents/skills/wf-ship/scripts/find-working-notes.sh '<ID>'"

# wf-ship puts this script's `target=` values into an `rm -rf` that the user
# runs, so a wrong answer is a file deleted by hand. The cases test two things:
# which paths match (both identifier bounds, ignored and untracked files, never
# tracked files), and that a shell reads each `target=` back as exactly the
# matched file. A path that git quoted, or a nested repository, is never a
# `target=`.

# A new repo that ignores plans/, with the current directory at its top and
# $ROOT set to the top as git names it. It is under $BATS_TEST_TMPDIR, so bats
# removes it, and never in the dotfiles working tree, which AGENTS.md forbids.
new_repo() {
  local tmp
  tmp="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet .
  printf 'plans/\n' > .gitignore
  git add .gitignore
  git commit --quiet -m seed
  ROOT="$(git rev-parse --show-toplevel)"
}

# note <path>: creates an untracked file and its directories.
note() {
  mkdir -p "$(dirname "$1")"
  printf 'x\n' > "$1"
}

run_script() {
  run bash "$SCRIPT" "$@"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
}

# read_back <value>: the single word that a shell makes of one `target=` value,
# as the pasted `rm -rf` reads it. Fails when the value is not exactly one word.
read_back() {
  eval "set -- $1"
  [ "$#" -eq 1 ] || return 1
  printf '%s' "$1"
}

# ─── the skill still calls the script ──────────────────────────────────────

@test "wf-ship calls the working-notes search once, alone in its block" {
  assert_sole_call "$SKILL" "$CALL"
}

# ─── which paths come back ─────────────────────────────────────────────────

@test "an ignored note and an untracked note are both found" {
  new_repo
  note plans/2026-09-12-zzz-0-plan.md
  note notes/zzz-0.md
  [ -n "$(git check-ignore plans/2026-09-12-zzz-0-plan.md)" ]

  run_script ZZZ-0
  [ "$(output_values target)" = "$(printf "'%s'\n'%s'" "$ROOT/notes/zzz-0.md" "$ROOT/plans/2026-09-12-zzz-0-plan.md")" ]
}

@test "a tracked note is not a candidate" {
  new_repo
  note docs/zzz-0-spec.md
  git add docs
  git commit --quiet -m spec
  note notes/zzz-0.md

  run_script ZZZ-0
  [ "$(output_values target)" = "'$ROOT/notes/zzz-0.md'" ]
}

# The left bound keeps an identifier out of a longer run of letters, and the
# right bound out of a longer run of digits. The matching note makes sure that
# neither bound passes because nothing matched.
@test "DX-5 matches neither a dx-57 path nor an adx-5 one" {
  new_repo
  note notes/dx-57-other.md
  note notes/adx-5-other.md
  note notes/dx-5-mine.md

  run_script DX-5
  [ "$(output_values target)" = "'$ROOT/notes/dx-5-mine.md'" ]
}

@test "run from a subdirectory, targets are still absolute from the top" {
  new_repo
  note notes/zzz-0.md
  mkdir sub
  cd sub || fail "cd sub failed"

  run_script ZZZ-0
  [ "$(output_values target)" = "'$ROOT/notes/zzz-0.md'" ]
}

@test "matching nothing exits 0 with no output" {
  new_repo
  note notes/zzz-1.md

  run bash "$SCRIPT" ZZZ-0
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── what a shell makes of each target ─────────────────────────────────────

@test "a note whose path holds a space prints as one target" {
  new_repo
  note 'my notes/zzz-0 plan.md'

  run_script ZZZ-0
  [ "$(output_values target | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(read_back "$(output_values target)")" = "$ROOT/my notes/zzz-0 plan.md" ]
}

@test "a path holding a single quote reads back unchanged, and nothing in it runs" {
  new_repo
  note "it's/zzz-0-a'b'c.md"

  run_script ZZZ-0
  [ "$(read_back "$(output_values target)")" = "$ROOT/it's/zzz-0-a'b'c.md" ]

  new_repo
  note 'zzz-0-$(touch pwn).md'
  note 'zzz-0-;touch pwn2.md'

  run_script ZZZ-0
  local t
  while IFS= read -r t; do
    case "$(read_back "$t")" in
      "$ROOT/zzz-0-\$(touch pwn).md"|"$ROOT/zzz-0-;touch pwn2.md") ;;
      *) fail "a target read back as something else: $t" ;;
    esac
  done < <(output_values target)
  [ "$(output_values target | wc -l | tr -d ' ')" -eq 2 ]
  [ ! -e pwn ] && [ ! -e pwn2 ] || fail "reading a target back ran a command"
}

@test "a non-ASCII note prints as a plain target" {
  new_repo
  note 'zzz-0-café.md'

  run_script ZZZ-0
  [ -z "$(output_values unquotable)" ]
  [ "$(read_back "$(output_values target)")" = "$ROOT/zzz-0-café.md" ]
}

# git prints a name that it must escape in escaped form. That text is not the
# file name, so no quoting makes it a correct target. The newline directory is
# the dangerous case: from -z output with newlines put back, it gives a bare
# `../` line.
@test "every path git quoted is unquotable and never a target" {
  new_repo
  local dir
  dir="$(printf 'nl\n..')"
  mkdir "$dir"
  printf 'x\n' > "$dir/zzz-0-in-nl-dir.md"
  note 'dq"zzz-0.md'
  note 'bs\zzz-0.md'

  run_script ZZZ-0
  [ -z "$(output_values target)" ] || fail "a quoted path became a target: $output"
  [ "$(output_values unquotable)" = "$(printf '%s\n' '"bs\\zzz-0.md"' '"dq\"zzz-0.md"' '"nl\n../zzz-0-in-nl-dir.md"')" ] \
    || fail "unexpected unquotable lines: $output"
  [ -z "$(printf '%s\n' "$output" | grep -vE '^(target|unquotable)=')" ] \
    || fail "a line started without a key: $output"
}

# git lists a directory that holds its own repository, a worktree included, as
# one `dir/` line. As a target, it deletes that whole checkout.
@test "a nested repository or worktree naming the identifier is never a target" {
  new_repo
  note plans/zzz-0-plan.md
  git worktree add --quiet -b zzz-0-other plans/zzz-0-other
  git init --quiet notes/zzz-0-emb

  run_script ZZZ-0
  [ "$(output_values target)" = "'$ROOT/plans/zzz-0-plan.md'" ] || fail "unexpected targets: $output"
  [ "$(output_values nested)" = "$(printf '%s\n' "$ROOT/notes/zzz-0-emb/" "$ROOT/plans/zzz-0-other/")" ] \
    || fail "unexpected nested lines: $output"
}

# The identifier can name a directory, not a file. Each file under it, at any
# depth and in any letter case, is a separate target.
@test "files under a directory named for the identifier are each a target" {
  new_repo
  note plans/zzz-0-dir/a.md
  note plans/zzz-0-dir/deep/b.md
  note 'notes/ZZZ-0 caps/c.md'

  run_script ZZZ-0
  [ "$(output_values target)" = "$(printf "'%s'\n'%s'\n'%s'" "$ROOT/notes/ZZZ-0 caps/c.md" "$ROOT/plans/zzz-0-dir/a.md" "$ROOT/plans/zzz-0-dir/deep/b.md")" ] \
    || fail "unexpected targets: $output"
}

# ─── the argument ──────────────────────────────────────────────────────────

@test "an argument that is not an identifier exits 2" {
  new_repo
  note notes/zzz-0.md

  local arg
  for arg in '' zzz ZZZ- -rf 'ZZZ-0 ' 'ZZZ-0;x' '.*' "$(printf 'ZZZ-0\nfoo')"; do
    run bash "$SCRIPT" "$arg"
    [ "$status" -eq 2 ] || fail "accepted a non-identifier ($status): $arg"
    [ -z "$(output_values target)" ] || fail "printed a target for a non-identifier: $arg"
  done

  run bash "$SCRIPT"
  [ "$status" -eq 2 ]
  run bash "$SCRIPT" ZZZ-0 ZZZ-1
  [ "$status" -eq 2 ]
}

# ─── portability ───────────────────────────────────────────────────────────

@test "the search answers identically under /bin/bash and PATH's bash" {
  new_repo
  note plans/zzz-0-plan.md
  note "it's notes/zzz-0.md"
  note 'dq"zzz-0.md'

  assert_script_portable : "$SCRIPT" ZZZ-0

  [ "$(output_values target | wc -l | tr -d ' ')" -eq 2 ] || fail "unexpected output: $output"
  [ "$(output_values unquotable | wc -l | tr -d ' ')" -eq 1 ] || fail "unexpected output: $output"
}
