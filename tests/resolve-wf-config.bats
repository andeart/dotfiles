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
