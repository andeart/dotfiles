#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"
SCRIPT="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/find-working-notes.sh"
CALL="bash ~/.agents/skills/wf-ship/scripts/find-working-notes.sh '<ID>'"

# wf-ship pastes this script's `target=` values into an `rm -rf` the user runs,
# so a wrong answer here is a file deleted by hand. The cases grade two things:
# which paths come back - both identifier bounds, ignored and untracked, never
# tracked - and that every `target=` a shell reads back names exactly the file
# it matched, with any path git had to escape, and any nested repository, kept
# out of `target=` altogether.

# A fresh repo ignoring plans/, cd'd into, with $ROOT as git names its top. Under
# $BATS_TEST_TMPDIR so bats clears it, and never inside the dotfiles working
# tree - AGENTS.md forbids a test writing there.
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

# note <path>: an untracked file, with its directories.
note() {
  mkdir -p "$(dirname "$1")"
  printf 'x\n' > "$1"
}

run_script() {
  run bash "$SCRIPT" "$@"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
}

# vals <key>: every value of a `key=value` line, one per line.
vals() { printf '%s\n' "$output" | sed -n "s/^$1=//p"; }

# read_back <value>: the single word a shell makes of one `target=` value, the
# way the pasted `rm -rf` reads it. Fails when it is not exactly one word.
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
  [ "$(vals target)" = "$(printf "'%s'\n'%s'" "$ROOT/notes/zzz-0.md" "$ROOT/plans/2026-09-12-zzz-0-plan.md")" ]
}

@test "a tracked note is not a candidate" {
  new_repo
  note docs/zzz-0-spec.md
  git add docs
  git commit --quiet -m spec
  note notes/zzz-0.md

  run_script ZZZ-0
  [ "$(vals target)" = "'$ROOT/notes/zzz-0.md'" ]
}

# The left bound keeps an identifier out of a longer run of letters, the right
# out of a longer run of digits. The matching note is there so neither half can
# pass by finding nothing at all.
@test "DX-5 matches neither a dx-57 path nor an adx-5 one" {
  new_repo
  note notes/dx-57-other.md
  note notes/adx-5-other.md
  note notes/dx-5-mine.md

  run_script DX-5
  [ "$(vals target)" = "'$ROOT/notes/dx-5-mine.md'" ]
}

@test "run from a subdirectory, targets are still absolute from the top" {
  new_repo
  note notes/zzz-0.md
  mkdir sub
  cd sub || fail "cd sub failed"

  run_script ZZZ-0
  [ "$(vals target)" = "'$ROOT/notes/zzz-0.md'" ]
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
  [ "$(vals target | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(read_back "$(vals target)")" = "$ROOT/my notes/zzz-0 plan.md" ]
}

@test "a path holding a single quote reads back unchanged, and nothing in it runs" {
  new_repo
  note "it's/zzz-0-a'b'c.md"

  run_script ZZZ-0
  [ "$(read_back "$(vals target)")" = "$ROOT/it's/zzz-0-a'b'c.md" ]

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
  done < <(vals target)
  [ "$(vals target | wc -l | tr -d ' ')" -eq 2 ]
  [ ! -e pwn ] && [ ! -e pwn2 ] || fail "reading a target back ran a command"
}

@test "a non-ASCII note prints as a plain target" {
  new_repo
  note 'zzz-0-café.md'

  run_script ZZZ-0
  [ -z "$(vals unquotable)" ]
  [ "$(read_back "$(vals target)")" = "$ROOT/zzz-0-café.md" ]
}

# A name git has to escape prints as git's escaped form, which is not the file's
# name, so no quoting makes it a correct target. The newline directory is the
# dangerous one: re-joined from -z output it yields a bare `../` line.
@test "every path git quoted is unquotable and never a target" {
  new_repo
  local dir
  dir="$(printf 'nl\n..')"
  mkdir "$dir"
  printf 'x\n' > "$dir/zzz-0-in-nl-dir.md"
  note 'dq"zzz-0.md'
  note 'bs\zzz-0.md'

  run_script ZZZ-0
  [ -z "$(vals target)" ] || fail "a quoted path became a target: $output"
  [ "$(vals unquotable)" = "$(printf '%s\n' '"bs\\zzz-0.md"' '"dq\"zzz-0.md"' '"nl\n../zzz-0-in-nl-dir.md"')" ] \
    || fail "unexpected unquotable lines: $output"
  [ -z "$(printf '%s\n' "$output" | grep -vE '^(target|unquotable)=')" ] \
    || fail "a line started without a key: $output"
}

# git lists a directory holding its own repository, a worktree included, as one
# `dir/` entry. As a target it would delete that whole checkout.
@test "a nested repository or worktree naming the identifier is never a target" {
  new_repo
  note plans/zzz-0-plan.md
  git worktree add --quiet -b zzz-0-other plans/zzz-0-other
  git init --quiet notes/zzz-0-emb

  run_script ZZZ-0
  [ "$(vals target)" = "'$ROOT/plans/zzz-0-plan.md'" ] || fail "unexpected targets: $output"
  [ "$(vals nested)" = "$(printf '%s\n' "$ROOT/notes/zzz-0-emb/" "$ROOT/plans/zzz-0-other/")" ] \
    || fail "unexpected nested lines: $output"
}

# ─── the argument ──────────────────────────────────────────────────────────

@test "an argument that is not an identifier exits 2" {
  new_repo
  note notes/zzz-0.md

  local arg
  for arg in '' zzz ZZZ- -rf 'ZZZ-0 ' 'ZZZ-0;x' '.*' "$(printf 'ZZZ-0\nfoo')"; do
    run bash "$SCRIPT" "$arg"
    [ "$status" -eq 2 ] || fail "accepted a non-identifier ($status): $arg"
    [ -z "$(vals target)" ] || fail "printed a target for a non-identifier: $arg"
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

  [ "$(vals target | wc -l | tr -d ' ')" -eq 2 ] || fail "unexpected output: $output"
  [ "$(vals unquotable | wc -l | tr -d ' ')" -eq 1 ] || fail "unexpected output: $output"
}
