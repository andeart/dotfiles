#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_WF_LIB_ONLY=1 source "$0"; "$@"' "$RESOLVE" "$@"
}

# repo <name>: create a fixture repo root under the test tmpdir and print it.
# No git init - resolution reads the filesystem, not the index.
repo() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  printf '%s\n' "$root"
}

# config <root> <body>: write .wf.yml at the repo root.
config() {
  printf '%s\n' "$2" > "$1/.wf.yml"
}

# resolve <root> [args...]: run the script, keeping stdout and stderr apart so
# assertions read the answer rather than the explanation.
resolve() {
  local root="$1"; shift
  run --separate-stderr bash "$RESOLVE" --repo-root "$root" "$@"
}

# value <key>: print the resolved value for one key from $output.
value() {
  printf '%s\n' "$output" | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1) }'
}

# ─── flags & usage ─────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run bash "$RESOLVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: resolve-wf-config.sh"* ]]
}

@test "an unknown flag exits 2" {
  run bash "$RESOLVE" --nope
  [ "$status" -eq 2 ]
}

@test "--repo-root with no value exits 2" {
  run bash "$RESOLVE" --repo-root
  [ "$status" -eq 2 ]
}

@test "--repo-root with an empty value exits 2" {
  run bash "$RESOLVE" --repo-root ""
  [ "$status" -eq 2 ]
}

@test "a nonexistent --repo-root exits 2" {
  run bash "$RESOLVE" --repo-root "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 2 ]
}

# ─── no config at all ──────────────────────────────────────────────────────

@test "a repo with no .wf.yml resolves every default" {
  local root; root="$(repo bare)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Shaping" ]
  [ "$(value states.implementing)" = "Implementing" ]
  [ "$(value states.in-review)" = "In Review" ]
  [ "$(value workspace.impl)" = "base" ]
  [ "$(value ship.draft-by-default)" = "true" ]
  [ "$(value wrap.watch-post-merge-ci)" = "false" ]
}

@test "the default roster is the four reviewers, in order" {
  local root; root="$(repo bare-roster)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Alia" ]
  [ "$(value review.reviewers.2)" = "Bheem" ]
  [ "$(value review.reviewers.3)" = "Cristo" ]
  [ "$(value review.reviewers.4)" = "Darius" ]
  [ -z "$(value review.reviewers.5)" ]
}

@test "the default focus list carries the four headings" {
  local root; root="$(repo bare-focus)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.focus.1)" = "Security hardening" ]
  [ "$(value review.focus.4)" = "Succinct documentation that's not unnecessarily elaborate" ]
}

# There is no sensible default test command, and guessing one would run
# something arbitrary in a repo that never asked for it. Absent means the skill
# runs nothing and says so.
@test "ship.test-commands has no default members" {
  local root; root="$(repo bare-tests)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ship.test-commands"* ]]
}

# Deliberate divergence from resolve-tracker.sh, which falls back to tmp/ for
# public repos where a root-level tracker config would look out of place.
# Nothing in .wf.yml wants hiding, so the fallback would only add a place to
# look when a setting appears not to apply.
@test "tmp/.wf.yml is not read" {
  local root; root="$(repo tmp-only)"
  mkdir -p "$root/tmp"
  printf 'states:\n  shaping: FromTmp\n' > "$root/tmp/.wf.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Shaping" ]
}

# ─── library mode ──────────────────────────────────────────────────────────

@test "library mode defines functions without resolving anything" {
  call is_known_shape states.shaping
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "shape_of replaces a trailing list index with N" {
  call shape_of review.reviewers.3
  [ "$status" -eq 0 ]
  [ "$output" = "review.reviewers.N" ]
}

@test "config_path prints nothing when there is no .wf.yml" {
  local root; root="$(repo no-config)"
  call config_path "$root"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── reading a config ──────────────────────────────────────────────────────

@test "a scalar in the file wins over its default" {
  local root; root="$(repo scalar-override)"
  config "$root" 'states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Designing" ]
}

@test "keys the file leaves out still resolve to their defaults" {
  local root; root="$(repo partial)"
  config "$root" 'states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.implementing)" = "Implementing" ]
  [ "$(value workspace.impl)" = "base" ]
}

@test "a value containing spaces survives intact" {
  local root; root="$(repo spacey)"
  config "$root" 'states:
  in-review: Waiting On Review'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.in-review)" = "Waiting On Review" ]
}

# yq props uses " = " as its separator, so splitting on every occurrence would
# truncate any command carrying a flag assignment.
@test "a value containing an equals sign survives intact" {
  local root; root="$(repo equals)"
  config "$root" 'ship:
  test-commands:
    - make TARGET=all test'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value ship.test-commands.1)" = "make TARGET=all test" ]
}

@test "a block sequence parses" {
  local root; root="$(repo block-list)"
  config "$root" 'review:
  reviewers:
    - Ana
    - Bo'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Ana" ]
  [ "$(value review.reviewers.2)" = "Bo" ]
}

# yq normalises both list syntaxes, so accepting each costs nothing and
# rejecting one would be a rule with no reason behind it.
@test "an inline sequence parses the same way" {
  local root; root="$(repo inline-list)"
  config "$root" 'review:
  reviewers: [Ana, Bo]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Ana" ]
  [ "$(value review.reviewers.2)" = "Bo" ]
}

# Merging instead would mean a two-name roster silently ran six cycles.
@test "a list in the file replaces the default rather than appending to it" {
  local root; root="$(repo list-replace)"
  config "$root" 'review:
  reviewers: [Ana, Bo]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.2)" = "Bo" ]
  [ -z "$(value review.reviewers.3)" ]
}

@test "list indices in the dump are 1-based" {
  local root; root="$(repo one-based)"
  config "$root" 'review:
  reviewers: [Ana]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review.reviewers.1=Ana"* ]]
  [[ "$output" != *"review.reviewers.0="* ]]
}

@test "an empty .wf.yml resolves every default" {
  local root; root="$(repo empty-file)"
  : > "$root/.wf.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Shaping" ]
  [ "$(value review.reviewers.4)" = "Darius" ]
}

@test "an empty section resolves that section's defaults" {
  local root; root="$(repo empty-section)"
  config "$root" 'review: {}'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Alia" ]
}

# The dump is an interface: a skill reads it and bats asserts on it, so the
# order must not depend on how the file happened to be written.
@test "output order is canonical regardless of the file's own order" {
  local root; root="$(repo ordering)"
  config "$root" 'wrap:
  watch-post-merge-ci: true
states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  local first last
  first="$(printf '%s\n' "$output" | head -1)"
  last="$(printf '%s\n' "$output" | tail -1)"
  [ "$first" = "states.shaping=Designing" ]
  [ "$last" = "wrap.watch-post-merge-ci=true" ]
}

# ─── validation ────────────────────────────────────────────────────────────

# Silently ignoring a key means a setting that appears to apply and does not,
# which is worse than a file that will not load.
@test "an unknown top-level section exits 3 and names it" {
  local root; root="$(repo unknown-section)"
  config "$root" 'bogus:
  thing: 1'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: bogus.thing"* ]]
}

@test "an unknown key inside a known section exits 3 and names it" {
  local root; root="$(repo unknown-key)"
  config "$root" 'ship:
  draft-by-defualt: true'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: ship.draft-by-defualt"* ]]
}

# The bare "unknown key" would send the reader hunting for a typo that is not
# there, so the shape mismatch says which of the two it is.
@test "a scalar where a list belongs says so" {
  local root; root="$(repo scalar-for-list)"
  config "$root" 'review:
  reviewers: Ana'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers must be a list"* ]]
}

@test "a list where a scalar belongs says so" {
  local root; root="$(repo list-for-scalar)"
  config "$root" 'workspace:
  impl: [base]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"workspace.impl must be a single value"* ]]
}

# A key written with no value reads as deliberate, so taking the default would
# quietly do something other than what the file says.
@test "a key present with an empty value exits 3" {
  local root; root="$(repo empty-value)"
  config "$root" 'states:
  shaping:'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

# yq hands `null` and `~` through as literal strings, so the bare-key check
# alone would let two of YAML's three spellings of "no value" resolve as if
# they were the value.
@test "a key set to null exits 3" {
  local root; root="$(repo null-value)"
  config "$root" 'states:
  shaping: null'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

@test "a key set to a tilde exits 3" {
  local root; root="$(repo tilde-value)"
  config "$root" 'states:
  shaping: ~'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

@test "an out-of-range workspace.impl exits 3 and lists the choices" {
  local root; root="$(repo bad-enum)"
  config "$root" 'workspace:
  impl: sandbox'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"workspace.impl must be base or worktree"* ]]
}

@test "workspace.impl accepts worktree" {
  local root; root="$(repo good-enum)"
  config "$root" 'workspace:
  impl: worktree'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value workspace.impl)" = "worktree" ]
}

@test "a non-boolean ship.draft-by-default exits 3" {
  local root; root="$(repo bad-bool)"
  config "$root" 'ship:
  draft-by-default: yes'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"ship.draft-by-default must be true or false"* ]]
}

@test "a non-boolean wrap.watch-post-merge-ci exits 3" {
  local root; root="$(repo bad-bool-wrap)"
  config "$root" 'wrap:
  watch-post-merge-ci: 1'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"wrap.watch-post-merge-ci must be true or false"* ]]
}

@test "a valid config passes validation and resolves" {
  local root; root="$(repo valid)"
  config "$root" 'workspace:
  impl: worktree
ship:
  draft-by-default: false
  test-commands:
    - bats tests/'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value ship.draft-by-default)" = "false" ]
  [ "$(value ship.test-commands.1)" = "bats tests/" ]
}

# ─── this repo's own config ────────────────────────────────────────────────

# The resolver's rejection paths are only useful if the file they guard is
# actually valid, and this is the one .wf.yml that ships in the repo.
@test "the repo's own .wf.yml resolves cleanly" {
  run --separate-stderr bash "$RESOLVE" --repo-root "$DOTFILES_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value workspace.impl)" = "base" ]
  [ "$(value wrap.watch-post-merge-ci)" = "true" ]
}
