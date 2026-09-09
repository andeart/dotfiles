#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

HOOK="$DOTFILES_ROOT/claude/hooks/copy-into-worktree.sh"
RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"
BASE_CLONE="$DOTFILES_ROOT/agents/skills/git-conventions/scripts/base-clone.sh"

# Fresh world per test. Sets:
#   $BASE — a git clone holding one commit
#   $WT   — a linked worktree of it
#   $HOME — a fake home carrying the resolver, and the helper it sources, where
#           the hook looks for them
#
# The hook resolves the base clone from the worktree's own .git pointer, so
# these have to be a real worktree pair rather than two directories: the
# back-reference check the resolver performs is exactly what a fixture of
# plain directories would skip.
setup() {
  WORK="$(mktemp -d)"
  BASE="$WORK/base"
  WT="$WORK/wt"

  export HOME="$WORK/home"
  mkdir -p "$HOME/.agents/skills/wf-conventions/scripts" \
           "$HOME/.agents/skills/git-conventions/scripts"
  cp "$RESOLVE" "$HOME/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh"
  # Both the hook and the resolver source this, so a fake home carrying only the
  # resolver is a half-deployed one - the hook then fails open and 12 of this
  # file's cases go red.
  cp "$BASE_CLONE" "$HOME/.agents/skills/git-conventions/scripts/base-clone.sh"

  mkdir -p "$BASE"
  git -C "$BASE" init -q
  echo "tracked" > "$BASE/README.md"
  git -C "$BASE" add README.md
  git -C "$BASE" commit -qm "first"
}

# wf_config <yaml-for-the-workspace-key>: write and commit a .wf.yml declaring
# only what these tests read. The resolver rejects an unknown key, not an
# absent one, so a partial file resolves fine.
wf_config() {
  printf 'workspace:\n  impl: worktree\n%s\n' "$1" > "$BASE/.wf.yml"
  git -C "$BASE" add .wf.yml
  git -C "$BASE" commit -qm "config"
}

add_worktree() {
  git -C "$BASE" worktree add -q -b feature "$WT" >/dev/null 2>&1
}

# payload [worktree-path]: the PostToolUse envelope the hook parses. Defaults
# to the real worktree; a caller passes a path to test the response's own field.
payload() {
  jq -cn --arg wt "${1:-$WT}" \
    '{tool_name: "EnterWorktree", cwd: $wt, tool_response: {worktreePath: $wt}}'
}

run_hook() {
  run bash -c 'payload=$(cat); printf "%s" "$payload" | bash "$1"' _ "$HOOK" <<< "$(payload "$@")"
}

# stat's mode flag is not portable: BSD stat (macOS) spells it -f '%Lp', while
# GNU stat (Linux CI) reads -f as --file-system and wants -c '%a'. GNU goes
# first so that the failing branch is a BSD usage error, which exits non-zero.
file_mode() {
  stat -c '%a' "$1" 2>/dev/null || stat -f '%Lp' "$1"
}

# ─── copying ───────────────────────────────────────────────────────────────────

@test "copies a listed path the worktree does not have" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo '{"env":"dev"}' > "$BASE/config/dev.json"
  add_worktree
  [ ! -e "$WT/config/dev.json" ]

  run_hook
  [ "$status" -eq 0 ]
  [ "$(cat "$WT/config/dev.json")" = '{"env":"dev"}' ]
  [[ "$output" == *"config/dev.json"* ]]
}

@test "creates the parent directory a copied path needs" {
  wf_config '  copy-into-worktree:
    - deep/nested/local.env'
  mkdir -p "$BASE/deep/nested"
  echo "SECRET=1" > "$BASE/deep/nested/local.env"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ -f "$WT/deep/nested/local.env" ]
}

@test "preserves the mode, so a 600 credentials file does not widen" {
  wf_config '  copy-into-worktree:
    - creds.json'
  echo '{"token":"x"}' > "$BASE/creds.json"
  chmod 600 "$BASE/creds.json"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ "$(file_mode "$WT/creds.json")" = "600" ]
}

@test "copies a directory entry whole" {
  wf_config '  copy-into-worktree:
    - secrets'
  mkdir -p "$BASE/secrets/inner"
  echo "a" > "$BASE/secrets/one.txt"
  echo "b" > "$BASE/secrets/inner/two.txt"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ "$(cat "$WT/secrets/one.txt")" = "a" ]
  [ "$(cat "$WT/secrets/inner/two.txt")" = "b" ]
}

@test "falls back to cwd when the response carries no worktree path" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
    "$(jq -cn --arg wt "$WT" '{tool_name: "EnterWorktree", cwd: $wt, tool_response: {}}')"
  [ "$status" -eq 0 ]
  [ -f "$WT/config/dev.json" ]
}

# The fallback above is for a response shape that changed, not for one that
# failed. A failed EnterWorktree leaves the session in the tree it was already
# in, and .cwd names that one.
@test "a response reporting failure gets no cwd fallback" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
    "$(jq -cn --arg wt "$WT" '{tool_name: "EnterWorktree", cwd: $wt, tool_response: {error: "worktree already exists"}}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

# ─── what it must not do ───────────────────────────────────────────────────────

@test "never overwrites a path the worktree already has, and says it left it" {
  wf_config '  copy-into-worktree:
    - README.md'
  echo "base version" > "$BASE/README.md"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ "$(cat "$WT/README.md")" = "tracked" ]
  [[ "$output" == *"Already in the worktree"* ]]
  [[ "$output" == *"README.md"* ]]
}

# The case the report exists for. A directory entry is declined as one unit, so
# a `config/` that git materialised for its tracked member does not pick up the
# gitignored sibling beside it - the report is the only thing that tells the
# user their untracked file stayed behind.
@test "a directory present for a tracked file is left whole, siblings and all" {
  wf_config '  copy-into-worktree:
    - config'
  mkdir -p "$BASE/config"
  echo '{"env":"prod"}' > "$BASE/config/prod.json"
  git -C "$BASE" add config/prod.json
  git -C "$BASE" commit -qm "tracked config"
  echo '{"env":"dev"}' > "$BASE/config/dev.json"
  add_worktree
  [ -f "$WT/config/prod.json" ]

  run_hook
  [ "$status" -eq 0 ]
  [ ! -e "$WT/config/dev.json" ]
  [[ "$output" == *"Already in the worktree"* ]]
  [[ "$output" == *"config"* ]]
}

@test "re-entering a seeded worktree copies nothing and reports why" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Copied into the worktree"*"config/dev.json"* ]]

  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"nothing"* ]]
  [[ "$output" == *"Already in the worktree"*"config/dev.json"* ]]
}

@test "skips an absolute entry and reports it, writing nothing" {
  wf_config '  copy-into-worktree:
    - /etc/hosts'
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped"* ]]
  [ ! -e "$WT/etc" ]
}

@test "reports an entry that climbs out of the repo" {
  wf_config '  copy-into-worktree:
    - ../escape.txt'
  echo "outside" > "$WORK/escape.txt"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped"* ]]
  [ "$(cat "$WORK/escape.txt")" = "outside" ]
}

# $BASE and $WT are siblings, so `../escape.txt` names one file from both and
# the test above passes with the `..` guard removed - the already-present check
# declines that copy on its own. A worktree one level deeper resolves the entry
# to a destination that does not exist, which is where the guard is the only
# thing between the entry and a write outside both trees.
@test "an entry that climbs out is stopped before it can write outside" {
  wf_config '  copy-into-worktree:
    - ../outside/new.txt'
  mkdir -p "$WORK/outside"
  echo "outside" > "$WORK/outside/new.txt"
  local deep="$WORK/deep/wt"
  git -C "$BASE" worktree add -q -b deep "$deep" >/dev/null 2>&1

  run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
    "$(jq -cn --arg wt "$deep" '{tool_name: "EnterWorktree", cwd: $wt, tool_response: {worktreePath: $wt}}')"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Skipped"* ]]
  [ ! -e "$WORK/deep/outside" ]
}

# Not an error, but not silent either: a mistyped entry and a correctly
# configured repo would otherwise produce the same empty output.
@test "a listed path absent from the base clone is named, not an error" {
  wf_config '  copy-into-worktree:
    - config/never-created.json'
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ ! -e "$WT/config/never-created.json" ]
  [[ "$output" == *"Not in the base clone"*"config/never-created.json"* ]]
}

# ─── when it does nothing at all ───────────────────────────────────────────────

@test "an empty list copies nothing and says nothing" {
  wf_config '  copy-into-worktree: []'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

@test "a repo that never declared the key is silent, not a halt" {
  printf 'workspace:\n  impl: worktree\n' > "$BASE/.wf.yml"
  git -C "$BASE" add .wf.yml
  git -C "$BASE" commit -qm "config"
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

@test "a .wf.yml the resolver rejects fails open" {
  printf 'workspace:\n  impl: sideways\n' > "$BASE/.wf.yml"
  git -C "$BASE" add .wf.yml
  git -C "$BASE" commit -qm "config"
  add_worktree

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "another tool's payload is ignored" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree

  run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
    "$(jq -cn --arg wt "$WT" '{tool_name: "Bash", cwd: $wt, tool_response: {worktreePath: $wt}}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

@test "an ordinary clone is not treated as a worktree" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"

  run bash -c 'printf "%s" "$2" | bash "$1"' _ "$HOOK" \
    "$(jq -cn --arg wt "$BASE" '{tool_name: "EnterWorktree", cwd: $wt, tool_response: {worktreePath: $wt}}')"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a missing resolver fails open rather than erroring" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree
  mv "$HOME/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh" "$WORK/moved.sh"

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

# A different failure from the one above with the same required outcome, and the
# state a partial `dotfiles push` leaves behind: the resolver is there and the
# helper both it and this hook source is not. The hook's own guard declines
# first, and the resolver would halt at 2 behind it.
@test "a missing shared helper fails open rather than erroring" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree
  mv "$HOME/.agents/skills/git-conventions/scripts/base-clone.sh" "$WORK/moved.sh"

  run_hook
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ ! -e "$WT/config/dev.json" ]
}

# The other half of a partial `dotfiles push`, and the half [ -f ] cannot see:
# the helper is present and truncated mid-definition. Sourcing it prints a
# syntax error and leaves base_clone undefined, so the redirect is what keeps
# both off the hook's streams - stdout is the JSON payload, and the child shell
# this replaced discarded the whole class. Asserted per stream rather than
# through run_hook, since which stream stayed clean is the point.
@test "a truncated shared helper fails open without printing" {
  wf_config '  copy-into-worktree:
    - config/dev.json'
  mkdir -p "$BASE/config"
  echo "x" > "$BASE/config/dev.json"
  add_worktree
  # Unterminated, so it is a syntax error at any length this file ever is.
  printf 'base_clone() {\n' > "$HOME/.agents/skills/git-conventions/scripts/base-clone.sh"

  run --separate-stderr bash -c 'payload=$(cat); printf "%s" "$payload" | bash "$1"' \
    _ "$HOOK" <<< "$(payload)"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$stderr" ]
  [ ! -e "$WT/config/dev.json" ]
}

@test "a malformed payload fails open" {
  run bash -c 'printf "%s" "not json" | bash "$1"' _ "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
