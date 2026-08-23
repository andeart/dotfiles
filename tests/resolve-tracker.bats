#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/work-item-conventions/scripts/resolve-tracker.sh"
REFERENCES="$DOTFILES_ROOT/agents/skills/work-item-conventions/references"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$0"; "$@"' "$RESOLVE" "$@"
}

# repo <name>: create a fixture repo root under the test tmpdir and print it.
# No git init - resolution reads the filesystem, not the index, so a work item
# can be filed from a tree with uncommitted config.
repo() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  printf '%s\n' "$root"
}

# config <root> <tracker> [body]: write one tracker config at the repo root.
config() {
  printf '%s\n' "${3:-}" > "$1/.workitems.$2.yml"
}

# resolve <root> [args...]: run the script, keeping stdout and stderr apart so
# assertions read the answer rather than the explanation.
resolve() {
  local root="$1"; shift
  run --separate-stderr bash "$RESOLVE" --repo-root "$root" "$@"
}

# ─── flags & usage ─────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run bash "$RESOLVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: resolve-tracker.sh"* ]]
}

@test "an unknown flag exits 2" {
  run bash "$RESOLVE" --nope
  [ "$status" -eq 2 ]
}

@test "--repo-root with no value exits 2" {
  run bash "$RESOLVE" --repo-root
  [ "$status" -eq 2 ]
}

@test "a nonexistent --repo-root exits 2" {
  run bash "$RESOLVE" --repo-root "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 2 ]
}

# ─── branch 1: an explicitly named tracker ─────────────────────────────────

@test "an explicit tracker resolves without consulting repo config" {
  local root; root="$(repo explicit-over-config)"
  config "$root" plane
  resolve "$root" --tracker jira
  [ "$status" -eq 0 ]
  [ "$output" = "jira" ]
}

@test "an explicit tracker resolves in a repo with no config at all" {
  local root; root="$(repo explicit-bare)"
  resolve "$root" --tracker github
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "an explicit tracker beats an otherwise-decisive default_tracker" {
  local root; root="$(repo explicit-over-default)"
  config "$root" plane "default_tracker: plane"
  config "$root" github
  resolve "$root" --tracker gitlab
  [ "$status" -eq 0 ]
  [ "$output" = "gitlab" ]
}

@test "an unknown explicit tracker exits 2 rather than falling back to detection" {
  local root; root="$(repo explicit-unknown)"
  config "$root" plane
  resolve "$root" --tracker linear
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unknown tracker: linear"* ]]
}

# ─── branch 2: exactly one config ──────────────────────────────────────────

@test "exactly one config resolves that tracker without prompting" {
  local root; root="$(repo single)"
  config "$root" plane
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

@test "a single config resolves with no default_tracker key present" {
  local root; root="$(repo single-no-default)"
  config "$root" github "assignee: octocat"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "a config under tmp/ resolves like one at the repo root" {
  local root; root="$(repo tmp-only)"
  mkdir -p "$root/tmp"
  printf '\n' > "$root/tmp/.workitems.jira.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "jira" ]
}

@test "the same tracker at both locations is one candidate, not two" {
  local root; root="$(repo root-and-tmp)"
  mkdir -p "$root/tmp"
  config "$root" plane
  printf '\n' > "$root/tmp/.workitems.plane.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

@test "config_path_for prefers the repo root over tmp/" {
  local root; root="$(repo root-wins)"
  mkdir -p "$root/tmp"
  config "$root" plane
  printf '\n' > "$root/tmp/.workitems.plane.yml"
  call config_path_for "$root" plane
  [ "$output" = "$root/.workitems.plane.yml" ]
}

# ─── branch 3: several configs, default_tracker decides ────────────────────

@test "default_tracker resolves when more than one config is present" {
  local root; root="$(repo multi-default)"
  config "$root" plane "default_tracker: github"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "default_tracker is honoured from whichever config carries it" {
  local root; root="$(repo multi-default-other-file)"
  config "$root" plane
  config "$root" github "default_tracker: plane"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

@test "two configs agreeing on default_tracker resolve it" {
  local root; root="$(repo multi-default-agree)"
  config "$root" plane "default_tracker: plane"
  config "$root" github "default_tracker: plane"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

# ─── branch 4: ask ─────────────────────────────────────────────────────────

@test "several configs and no default_tracker asks, listing the candidates" {
  local root; root="$(repo multi-ask)"
  config "$root" plane
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$output" == *"plane"* ]]
  [[ "$output" == *"github"* ]]
  [[ "$stderr" == *"none sets default_tracker"* ]]
}

@test "configs disagreeing on default_tracker ask rather than pick one" {
  local root; root="$(repo multi-conflict)"
  config "$root" plane "default_tracker: plane"
  config "$root" github "default_tracker: github"
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"disagree on default_tracker"* ]]
}

@test "a default_tracker naming an unconfigured tracker asks" {
  local root; root="$(repo multi-stale-default)"
  config "$root" plane "default_tracker: gitlab"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"has no config"* ]]
}

@test "no config at all asks and names both search locations" {
  local root; root="$(repo bare)"
  resolve "$root"
  [ "$status" -eq 10 ]
  [ -z "$output" ]
  [[ "$stderr" == *"$root"* ]]
  [[ "$stderr" == *"$root/tmp"* ]]
}

@test "the old .plane.yml filename is not a candidate" {
  local root; root="$(repo legacy-filename)"
  printf 'project: DX\n' > "$root/.plane.yml"
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"no .workitems."* ]]
}

# ─── declared_default (pure) ───────────────────────────────────────────────

@test "declared_default reads a bare value" {
  local root; root="$(repo dd-bare)"
  config "$root" plane "default_tracker: github"
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github" ]
}

@test "declared_default strips quotes and an inline comment" {
  local root; root="$(repo dd-messy)"
  config "$root" plane 'default_tracker: "github"   # the one I actually use'
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github" ]
}

@test "declared_default ignores a commented-out key" {
  local root; root="$(repo dd-commented)"
  config "$root" plane "# default_tracker: github"
  call declared_default "$root/.workitems.plane.yml"
  [ -z "$output" ]
}

@test "declared_default ignores a nested key" {
  local root; root="$(repo dd-nested)"
  config "$root" plane "guidance:
  default_tracker: github"
  call declared_default "$root/.workitems.plane.yml"
  [ -z "$output" ]
}

@test "a commented-out default_tracker leaves the run asking" {
  local root; root="$(repo commented-default)"
  config "$root" plane "# default_tracker: github"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"none sets default_tracker"* ]]
}

# ─── the tracker list and the reference files agree ────────────────────────

@test "every known tracker has a reference file" {
  call known_trackers
  [ "$status" -eq 0 ]
  local t
  for t in $output; do
    [ -f "$REFERENCES/$t.md" ] || {
      echo "no reference file for tracker '$t': $REFERENCES/$t.md" >&2
      return 1
    }
  done
}

@test "every reference file has a known tracker" {
  call known_trackers
  local known="$output" f base
  for f in "$REFERENCES"/*.md; do
    base="$(basename "$f" .md)"
    printf '%s\n' "$known" | grep -qx "$base" || {
      echo "reference file '$base.md' names no tracker resolve-tracker.sh knows" >&2
      return 1
    }
  done
}
