#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/work-item-conventions/scripts/resolve-tracker.sh"
REFERENCES="$DOTFILES_ROOT/agents/skills/work-item-conventions/references"
SKILLS="$DOTFILES_ROOT/agents/skills"
GH_SETTINGS="$DOTFILES_ROOT/bin/gh-set-default-settings"

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

@test "--repo-root with an empty value exits 2" {
  run bash "$RESOLVE" --repo-root ""
  [ "$status" -eq 2 ]
}

# An empty value clears the arity check but not the emptiness one. Without the
# second check it falls through to detection, which is the single thing naming a
# tracker is meant to rule out.
@test "--tracker with an empty value exits 2 rather than falling back to detection" {
  local root; root="$(repo empty-tracker)"
  config "$root" plane
  resolve "$root" --tracker ""
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--tracker needs a value"* ]]
  [ "$output" != "plane" ]
}

# Naming a tracker answers the question without opening a tree, so the answer
# must not depend on standing in one.
@test "an explicit tracker resolves even when the repo root does not exist" {
  run --separate-stderr bash "$RESOLVE" \
    --repo-root "$BATS_TEST_TMPDIR/absent" --tracker github
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
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

# The tracker list is checked one entry at a time. Matching against the joined
# list resolves any adjacent run of it, and this path has no second check behind
# it - it returned 0 naming "plane github", which is a reference file that does
# not exist. "File this in Plane and GitHub" is how a two-word value gets here.
@test "a multi-word tracker naming two real trackers exits 2" {
  run --separate-stderr bash "$RESOLVE" --tracker "plane github"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"unknown tracker: plane github"* ]]
  [ -z "$output" ]
}

@test "a multi-word tracker is rejected wherever it sits in the list" {
  run --separate-stderr bash "$RESOLVE" --tracker "jira gitlab"
  [ "$status" -eq 2 ]
  run --separate-stderr bash "$RESOLVE" --tracker "plane github jira gitlab"
  [ "$status" -eq 2 ]
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
  # Called directly and not through the `call` harness, which reads a return
  # value from stdout. This function assigns and prints nothing, so the same
  # shell that makes the assignment must echo it.
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    config_path_for "$2" plane
    printf "%s\n" "$CONFIG_PATH"' _ "$RESOLVE" "$root"
  [ "$status" -eq 0 ]
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

# A value carrying metacharacters is still just a value, and two independent
# mechanisms have to hold for that: is_known_tracker compares strings, and the
# candidate match uses `grep -qxF`, which would read the value as a regex without
# the -F. Either one alone leaves the other unpinned, so both a glob and a regex
# fixture belong here.
@test "a default_tracker that glob-matches a candidate is not treated as a pattern" {
  local root; root="$(repo multi-glob-default)"
  config "$root" plane "default_tracker: pla*"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [ "$output" != "pla*" ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker of '*' does not match every candidate" {
  local root; root="$(repo multi-glob-wildcard)"
  config "$root" plane 'default_tracker: "*"'
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [ "$output" != "*" ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker that regex-matches a candidate is not treated as a pattern" {
  local root; root="$(repo multi-regex-default)"
  config "$root" plane "default_tracker: p.ane"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [ "$output" != "p.ane" ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker of '.*' does not match every candidate" {
  local root; root="$(repo multi-wildcard-default)"
  config "$root" plane 'default_tracker: ".*"'
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [ "$output" != ".*" ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker with an interior hash asks rather than resolving" {
  local root; root="$(repo multi-interior-hash)"
  config "$root" plane "default_tracker: plane#x"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [ "$output" != "plane" ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker naming something that is not a tracker at all asks" {
  local root; root="$(repo multi-nonsense-default)"
  config "$root" plane "default_tracker: linear"
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"is not a tracker"* ]]
}

@test "a default_tracker with interior quotes asks rather than resolving" {
  local root; root="$(repo multi-inner-quotes)"
  config "$root" plane 'default_tracker: gi"th"ub'
  config "$root" github
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"is not a tracker"* ]]
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

@test "declared_default trims surrounding whitespace but keeps interior" {
  local root; root="$(repo dd-interior)"
  config "$root" plane "default_tracker:   git hub   "
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "git hub" ]
}

@test "declared_default strips surrounding quotes but keeps interior ones" {
  local root; root="$(repo dd-inner-quotes)"
  config "$root" plane 'default_tracker: gi"th"ub'
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = 'gi"th"ub' ]
}

@test "declared_default strips a quoted value padded with trailing whitespace" {
  local root; root="$(repo dd-quoted-padded)"
  config "$root" plane 'default_tracker: "github"   '
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github" ]
}

@test "declared_default keeps an interior hash but strips a real comment" {
  local root; root="$(repo dd-hash)"
  config "$root" plane "default_tracker: github#x"
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github#x" ]

  config "$root" plane "default_tracker: github # x"
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github" ]
}

@test "declared_default reads a value that is only a comment as unset" {
  local root; root="$(repo dd-hash-only)"
  config "$root" plane "default_tracker: # github"
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

# The lookups assign and print nothing, which keeps five command substitutions
# out of each sweep: four in discover_trackers' loop, and one around that loop.
# A caller that reads them through $() gives the whole saving back, so this
# grades both halves: the value is right, and it survives a read from the
# calling shell.
@test "config_path_for assigns CONFIG_PATH and prints nothing" {
  local root; root="$(repo assigns-config-path)"
  config "$root" plane
  # Two calls, and the difference is the point: the $() call runs the function
  # in a subshell, which discards the assignment.
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    config_path_for "$2" plane
    assigned="$CONFIG_PATH"
    printed="$(config_path_for "$2" plane)"
    printf "printed=[%s]\nassigned=%s\n" "$printed" "$assigned"' \
    _ "$RESOLVE" "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"printed=[]"* ]]
  [[ "$output" == *"assigned=$root/.workitems.plane.yml"* ]]
}

# A sweep calls this once per tracker in turn, so a value left from the last
# tracker reports every tracker as configured.
@test "config_path_for clears CONFIG_PATH when the tracker has no config" {
  local root; root="$(repo clears-config-path)"
  config "$root" plane
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    config_path_for "$2" plane
    config_path_for "$2" github
    printf "[%s]\n" "$CONFIG_PATH"' _ "$RESOLVE" "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "[]" ]
}

# The larger half of the same saving: a sweep read through $() pays a subshell
# for the loop, and four more inside it.
@test "discover_trackers assigns SEARCH_CANDIDATES and prints nothing" {
  local root; root="$(repo assigns-candidates)"
  config "$root" plane
  config "$root" github
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    discover_trackers "$2"
    assigned="$SEARCH_CANDIDATES"
    printed="$(discover_trackers "$2")"
    printf "printed=[%s]\nassigned=[%s]\n" "$printed" "$assigned"' \
    _ "$RESOLVE" "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"printed=[]"* ]]
  [[ "$output" == *"assigned=[plane"$'\n'"github]"* ]]
}

# ─── the base clone fallback ───────────────────────────────────────────────

# worktree <name>: build a linked-worktree pair the way git writes one. It
# writes a .git file that names the registration, and the registration's own
# gitdir that names this worktree back. It sets $BASE and $WT. It runs no git
# init, which keeps this suite filesystem-only. The back-reference is the whole
# of what the resolver verifies, and a fixture of plain directories skips it.
worktree() {
  BASE="$BATS_TEST_TMPDIR/$1/base"
  WT="$BATS_TEST_TMPDIR/$1/wt"
  local reg="$BASE/.git/worktrees/$1"
  mkdir -p "$reg" "$WT"
  printf 'gitdir: %s\n' "$reg" > "$WT/.git"
  printf '%s\n' "$WT/.git" > "$reg/gitdir"
}

# physical <dir>: <dir> with `..` and each symlink resolved, which is the form
# base_clone prints an inherited path in. An assertion against a literal $BASE
# passes on Linux and fails on macOS, where BATS_TEST_TMPDIR sits below a
# symlinked /var. A root's own path is used as it is, without this helper.
physical() {
  (cd "$1" && pwd -P)
}

@test "a worktree carrying its own config reads its own" {
  worktree own-config
  config "$WT" github
  config "$BASE" plane
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
}

@test "a worktree with no config of its own reads the base clone's" {
  worktree inherits
  config "$BASE" plane
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

# One directory answers the whole run. A per-tracker fallback fails this case:
# it reports both trackers, and sends a repo that resolves cleanly to an ask.
@test "a worktree's own config wins outright over the base clone's for another tracker" {
  worktree own-beats-base
  config "$WT" github
  config "$BASE" plane
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "github" ]
  [ -z "$stderr" ]
}

@test "neither the worktree nor its base clone carrying a config asks, naming the base clone" {
  worktree neither
  resolve "$WT"
  [ "$status" -eq 10 ]
  [ -z "$output" ]
  [[ "$stderr" == *"$(physical "$BASE")"* ]]
  [[ "$stderr" != *"$WT"* ]]
}

@test "the no-default message names the base clone the candidates came from" {
  worktree base-multi
  config "$BASE" plane
  config "$BASE" github
  resolve "$WT"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"none sets default_tracker"* ]]
  [[ "$stderr" == *"$(physical "$BASE")"* ]]
}

@test "the disagreement message names the base clone the candidates came from" {
  worktree base-conflict
  config "$BASE" plane "default_tracker: plane"
  config "$BASE" github "default_tracker: github"
  resolve "$WT"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"disagree on default_tracker"* ]]
  [[ "$stderr" == *"$(physical "$BASE")"* ]]
}

# config_path_for reads the base clone by its own rule, tmp/ included. tmp/
# holds a config that should not sit in a public tree, and a gitignored file
# does not travel into a worktree, so tmp/ holds the configs that need this
# fallback most.
@test "the base clone's tmp/ copy is consulted" {
  worktree base-tmp
  mkdir -p "$BASE/tmp"
  printf '\n' > "$BASE/tmp/.workitems.jira.yml"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "jira" ]
}

# The registration check, graded through this script and not through base_clone
# alone. The neighbour carries a config, so a run that skips the back-reference
# check resolves `plane` instead of an ask. This is not an authenticity check:
# base-clone.sh's header says what it proves and what it does not, and this case
# alone does not make an untrusted tree safe to resolve from.
@test "a .git file naming a directory that does not back-reference is not read from" {
  local root="$BATS_TEST_TMPDIR/no-backref"
  local evil="$BATS_TEST_TMPDIR/evil"
  mkdir -p "$root" "$evil/.git/worktrees/no-backref"
  config "$evil" plane
  printf 'gitdir: %s\n' "$evil/.git/worktrees/no-backref" > "$root/.git"
  resolve "$root"
  [ "$status" -eq 10 ]
  [ -z "$output" ]
  [[ "$stderr" == *"$root"* ]]
  [[ "$stderr" != *"$evil"* ]]
}

# An ordinary clone has a .git directory, so the is-a-file test in
# set_search_root declines before base_clone runs.
@test "an ordinary clone with a .git directory resolves without a fallback" {
  local root; root="$(repo ordinary-clone)"
  mkdir -p "$root/.git"
  config "$root" plane
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

# ─── --with-config-path ────────────────────────────────────────────────────

# A skill that resolves a tracker then reads that tracker's config. The path
# comes back on the call the skill already makes, which saves a second fork and
# a model round trip.

# key <name>: the value of one key=value line in $output.
key() {
  printf '%s\n' "$output" | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1) }'
}

@test "--with-config-path adds the path to a detected tracker" {
  local root; root="$(repo path-detect)"
  config "$root" plane
  resolve "$root" --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "plane" ]
  [ "$(key config_path)" = "$root/.workitems.plane.yml" ]
}

@test "--with-config-path reports the base clone's path from an inheriting worktree" {
  worktree path-inherits
  config "$BASE" plane
  resolve "$WT" --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "plane" ]
  [ "$(key config_path)" = "$(physical "$BASE")/.workitems.plane.yml" ]
}

@test "--with-config-path finds the base clone's tmp/ copy" {
  worktree path-inherits-tmp
  mkdir -p "$BASE/tmp"
  printf '\n' > "$BASE/tmp/.workitems.plane.yml"
  resolve "$WT" --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key config_path)" = "$(physical "$BASE")/tmp/.workitems.plane.yml" ]
}

@test "--tracker with --with-config-path prints both lines" {
  local root; root="$(repo path-explicit)"
  config "$root" github
  resolve "$root" --tracker github --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "github" ]
  [ "$(key config_path)" = "$root/.workitems.github.yml" ]
}

# /wf-ship's own invocation, and the only case that uses the explicit branch and
# the search root together. Without the flag, the explicit branch returns before
# it reaches the search root.
@test "--tracker with --with-config-path reaches the base clone from a worktree" {
  worktree path-explicit-inherits
  config "$BASE" plane
  resolve "$WT" --tracker plane --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "plane" ]
  [ "$(key config_path)" = "$(physical "$BASE")/.workitems.plane.yml" ]
}

# The contract /wf-ship branches on to reach its "no config exists" arm. An
# empty path is a real answer and not an ambiguity, because the flag validates
# the root.
@test "--tracker with --with-config-path prints an empty path when that tracker has no config" {
  local root; root="$(repo path-explicit-none)"
  config "$root" plane
  resolve "$root" --tracker github --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "github" ]
  [ "$(key config_path)" = "" ]
  [[ "$output" == *"config_path="* ]]
}

# The search root is decided by whether the root carries any config, and not by
# this tracker. So a worktree with a config of its own reports an empty path for
# another tracker, and does not read the base clone.
@test "a worktree with its own config reports an empty path for a tracker only the base clone has" {
  worktree path-no-mixing
  config "$WT" github
  config "$BASE" plane
  resolve "$WT" --tracker plane --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key config_path)" = "" ]
}

# The name is valid before it reaches a path: $tracker goes straight into
# $root/.workitems.$tracker.yml, so the order is the guarantee.
@test "--with-config-path with an unknown tracker exits 2" {
  local root; root="$(repo path-unknown-tracker)"
  config "$root" plane
  resolve "$root" --tracker linear --with-config-path
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

# A caller cannot tell an empty path from a nonexistent root apart from an empty
# path from a repo with no config. So the flag adds the root test that the
# explicit branch does without.
@test "--with-config-path against a missing root exits 2 rather than printing an empty path" {
  run --separate-stderr bash "$RESOLVE" \
    --repo-root "$BATS_TEST_TMPDIR/absent" --tracker github --with-config-path
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

@test "exit 10 under --with-config-path still prints the candidates bare" {
  local root; root="$(repo path-ask)"
  config "$root" plane
  config "$root" github
  resolve "$root" --with-config-path
  [ "$status" -eq 10 ]
  [[ "$output" == *"plane"* ]]
  [[ "$output" == *"github"* ]]
  [[ "$output" != *"tracker="* ]]
  [[ "$output" != *"config_path="* ]]
}

# The two streams carry different contracts. The four stderr messages are prose
# that a reader takes as one line. config_path= is a field that a skill reads by
# name, where a newline in a directory name makes a second field.
@test "a root carrying a control character exits 2 under --with-config-path" {
  local root="$BATS_TEST_TMPDIR/ctrl"$'\n'"x"
  mkdir -p "$root"
  config "$root" plane
  resolve "$root" --with-config-path
  [ "$status" -eq 2 ]
  [[ "$output" != *"config_path="* ]]
}

# The message names the flag and never the value. A message that holds the path
# moves the forgery from stdout to stderr and does not stop it: file-work-item
# reads exit 2 as "stop and show it", so a root named
# `<dir>\nconfig_path=/etc/passwd` reaches the user as the config_path= line
# that this run refuses to print.
@test "the control-character message does not echo the path it rejected" {
  local root="$BATS_TEST_TMPDIR/ctrl-quiet"$'\n'"config_path=/etc/passwd"
  mkdir -p "$root"
  config "$root" plane
  resolve "$root" --with-config-path
  [ "$status" -eq 2 ]
  [[ "$stderr" != *"config_path="* ]]
  [[ "$stderr" != *"/etc/passwd"* ]]
  [[ "$stderr" == *"resolve-tracker:"* ]]
  [[ "$stderr" == *"control character"* ]]
}

@test "a root carrying a control character still resolves without --with-config-path" {
  local root="$BATS_TEST_TMPDIR/ctrl-ok"$'\n'"x"
  mkdir -p "$root"
  config "$root" plane
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

@test "a root carrying a control character still prints its stderr message at exit 10" {
  local root="$BATS_TEST_TMPDIR/ctrl-ask"$'\n'"x"
  mkdir -p "$root"
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"no .workitems.<tracker>.yml under"* ]]
}

# unique_lines removes duplicates and counts in the shell, and forks nothing.
# That is the same fork class the lookups avoid, on the branch the base clone
# fallback routes worktrees onto.
@test "unique_lines keeps the distinct non-empty lines and counts them" {
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    for s in "" "plane" "plane
github" "

" "plane
plane" "github
plane
github"; do unique_lines "$s"
      printf "%s:[%s] " "$LINE_COUNT" "$(printf "%s" "$UNIQUE_LINES" | tr "\n" ",")"
    done' _ "$RESOLVE"
  [ "$status" -eq 0 ]
  [ "$output" = "0:[] 1:[plane] 2:[plane,github] 0:[] 1:[plane] 2:[github,plane] " ]
}

# First-occurrence order, and not alphabetical order, so the disagreement
# message below lists the defaults in the order the candidates print above it.
# Graded here because the order is observable in that message.
@test "the disagreement message lists defaults in candidate order" {
  local root; root="$(repo declared-order)"
  config "$root" plane 'default_tracker: github'
  config "$root" github 'default_tracker: plane'
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"disagree on default_tracker: github plane"* ]]
}

# has_line matches a literal value, which is the half that matters: a
# default_tracker value is file content, so a `*` in it must match literally and
# not against every candidate. A partial line does not match.
#
# A multi-line value matches when it is a run of full lines. resolve() calls
# this function only once n_declared is 1, so no run reaches that case. It is
# asserted here so the behaviour is on the record.
@test "has_line matches whole lines and never treats the value as a pattern" {
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    lines="plane
github"
    for v in plane github "*" lane jira "plane
github"; do
      if has_line "$lines" "$v"; then printf "y"; else printf "n"; fi
    done' _ "$RESOLVE"
  [ "$status" -eq 0 ]
  [ "$output" = "yynnny" ]
}

# The reason unique_lines takes one line at a time and does not split on IFS: a
# default_tracker value is file content, and a split leaves it unquoted, so a
# `*` expands against the working directory and counts the files there. The
# fixture directory holds two configs, so such a count is not 1, and the run
# takes an exit-10 branch other than the one asserted here.
@test "a default_tracker naming a glob is counted as one value, not expanded" {
  local root; root="$(repo glob-default)"
  config "$root" plane 'default_tracker: *'
  config "$root" github
  cd "$root"
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"which is not a tracker"* ]]
  [[ "$stderr" == *"'*'"* ]]
}

# ─── the tracker list and the reference files agree ────────────────────────

# discover_trackers appends one line per entry and resolve() counts the appends,
# so a repeated entry makes a one-config repo report two candidates and take the
# multi-config branch. The four cases below iterate the list and pass with a
# duplicate in it, so this case is the only one that catches it.
@test "the known tracker list has no repeated entry" {
  call known_trackers
  [ "$status" -eq 0 ]
  local all deduped
  all="$(printf '%s\n' "$output" | sort)"
  deduped="$(printf '%s\n' "$output" | sort -u)"
  [ "$all" = "$deduped" ] || {
    echo "KNOWN_TRACKERS repeats an entry: $output" >&2
    return 1
  }
}

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
    # `plane-creating.md` is the create-side half of `plane.md`, so the tracker
    # is the part before the suffix.
    base="$(basename "$f" .md)"
    base="${base%%-*}"
    printf '%s\n' "$known" | grep -qx "$base" || {
      echo "reference file '$(basename "$f")' names no tracker resolve-tracker.sh knows" >&2
      return 1
    }
  done
}

# Each skill reads its own half alongside the main reference, so both halves have
# to sit beside every reference that is not a skeleton, or that instruction sends
# a run at a file that isn't there. The converse matters too: a half beside a
# skeleton is a tracker that is implemented and says otherwise.
@test "both split halves sit beside every reference that is not a skeleton" {
  call known_trackers
  local t main half skeleton
  for t in $output; do
    main="$REFERENCES/$t.md"
    grep -q '^\*\*This reference is a skeleton' "$main" && skeleton=1 || skeleton=""
    for half in creating refining; do
      if [ -n "$skeleton" ]; then
        [ ! -e "$REFERENCES/$t-$half.md" ] || {
          echo "$t.md is a skeleton but $t-$half.md exists beside it" >&2
          return 1
        }
      else
        [ -f "$REFERENCES/$t-$half.md" ] || {
          echo "$t.md is implemented but $t-$half.md is missing" >&2
          return 1
        }
      fi
    done
  done
}

# Both skills name the implemented references inline, so a run that resolves to a
# skeleton stops without opening it - which is what keeps the skeletons off the
# permission allowlist and out of a run's context. That list is a second copy of
# a fact the reference files carry themselves, so pin the two together.
@test "the skills name exactly the references that are not skeletons" {
  call known_trackers
  local t implemented=""
  for t in $output; do
    grep -q '^\*\*This reference is a skeleton' "$REFERENCES/$t.md" \
      || implemented="$implemented$t "
  done
  implemented="$(printf '%s' "$implemented" | tr ' ' '\n' | grep . | sort | tr '\n' ' ')"
  [ -n "$implemented" ]

  local f named
  for f in "$SKILLS/file-work-item/SKILL.md" "$SKILLS/refine-work-item/SKILL.md"; do
    named="$(sed -n 's/^\*\*Implemented references: \(.*\)\.\*\*.*/\1/p' "$f" \
      | tr -d '`,' | tr ' ' '\n' | grep . | sort | tr '\n' ' ')"
    [ "$named" = "$implemented" ] || {
      echo "$f names [$named]; references say [$implemented]" >&2
      return 1
    }
  done
}

# ─── the two readers of the same file agree ────────────────────────────────

# resolve-tracker.sh and gh-set-default-settings both read top-level scalars out
# of a .workitems.plane.yml with their own not-a-YAML-parser, and the drift is
# invisible until a value lands in the wrong tracker or an autolink points at the
# wrong workspace, so pin them together. Every key both sides read in production
# is covered: declared_default is fixed to default_tracker, while the autolink
# reads project and workspace, and it is the value-scrubbing sequence rather than
# the key that drifts.
@test "declared_default and plane_config_value read the same value the same way" {
  local root; root="$(repo parser-agreement)"
  local file="$root/.workitems.plane.yml"
  local v a k b
  for v in 'github' '"github"' "'github'" '"github"   ' '  github  ' 'gi"th"ub' \
           '"github"  # note' 'github # x' '#github' 'git hub' 'p.ane' 'pla*' \
           '.*' '"gith ub" ' 'github#x' '"github#x"'; do
    printf 'default_tracker: %s\nproject: %s\nworkspace: %s\n' "$v" "$v" "$v" > "$file"
    a="$(bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"; declared_default "$2"' _ "$RESOLVE" "$file")"
    for k in default_tracker project workspace; do
      b="$(bash -c '_GH_SETTINGS_LIB_ONLY=1 source "$1"; plane_config_value "$2" "$3"' _ "$GH_SETTINGS" "$file" "$k")"
      [ "$a" = "$b" ] || {
        echo "disagree on [$v] via $k: declared_default=[$a] plane_config_value=[$b]" >&2
        return 1
      }
    done
  done
}

# The guard is an explicit [ -f ] and not the source's own failure, because
# `set -euo pipefail; . /nonexistent` exits 1 with a bash message that names the
# path but not the script. A broken install is not a usage error that the caller
# can fix with different arguments, but 2 already means "this invocation cannot
# proceed for an environment reason" here.
@test "a missing shared helper halts at 2, naming the file and the remedy" {
  local stage="$BATS_TEST_TMPDIR/half-deployed/work-item-conventions/scripts"
  mkdir -p "$stage"
  cp "$RESOLVE" "$stage/resolve-tracker.sh"
  run --separate-stderr bash "$stage/resolve-tracker.sh" --repo-root "$BATS_TEST_TMPDIR"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"resolve-tracker: missing"* ]]
  [[ "$stderr" == *"base-clone.sh"* ]]
  [[ "$stderr" == *"dotfiles push"* ]]
}

# Run from its own directory, the script's $0 has no slash, and a bare
# `${BASH_SOURCE[0]%/*}` gives the script's own name and not `.`. The guard
# above then reads a path that cannot exist, and tells a user with a complete
# install to run `dotfiles push`. Only a run from beside the script reaches
# this.
@test "the script resolves when run from its own directory" {
  local root; root="$(repo own-directory)"
  config "$root" plane
  run --separate-stderr bash -c 'cd "$1" && bash resolve-tracker.sh --repo-root "$2"' \
    _ "${RESOLVE%/*}" "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
  [ -z "$stderr" ]
}

# ─── bash 3.2 compatibility ────────────────────────────────────────────────

# The script's shebang resolves to bash 5.x on this machine's PATH, so a `bash
# -n` that passes proves nothing about the /bin/bash 3.2 that macOS ships. Only
# the parser of 3.2 itself proves that. CI runs Ubuntu, where /bin/bash is 5.x,
# so this case skips there and does not pass for free.
@test "the script parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$RESOLVE"
  [ "$status" -eq 0 ]
}

# ${BASH_SOURCE[0]} makes bash part of the library-mode contract, and the two
# callers that source this script use bash. A SKILL.md block runs in zsh and
# forks this script, which is what this case runs.
@test "a fork from zsh resolves through the base clone" {
  command -v zsh >/dev/null 2>&1 || skip "no zsh on PATH"
  worktree zsh-fork
  config "$BASE" plane
  run zsh -c 'bash "$1" --repo-root "$2" --with-config-path' _ "$RESOLVE" "$WT"
  [ "$status" -eq 0 ]
  [[ "$output" == *"tracker=plane"* ]]
}

# ─── the read-only guarantee ───────────────────────────────────────────────

# manifest <dir>: every path under dir, with a checksum for each regular file,
# so one comparison catches an added file, a removed one, and an edited one.
manifest() {
  find "$1" | sort | while IFS= read -r p; do
    if [ -f "$p" ]; then
      printf '%s %s\n' "$p" "$(cksum < "$p")"
    else
      printf '%s dir\n' "$p"
    fi
  done
}

# Every branch runs here, including the ones that exit non-zero - an error path is
# where a stray write is likeliest and least noticed.
@test "resolving never writes to the tree it reads" {
  local root; root="$(repo read-only)"
  mkdir -p "$root/single/tmp" "$root/multi" "$root/bare"
  printf 'project: DX\n' > "$root/single/tmp/.workitems.plane.yml"
  printf 'default_tracker: p.ane\n' > "$root/multi/.workitems.plane.yml"
  printf 'assignee: octocat\n' > "$root/multi/.workitems.github.yml"

  # The base clone branch is the first one that reads outside --repo-root, and
  # RESOLUTION.md cites this guarantee for the allowlist claim, so the pair
  # belongs inside the manifest. The base clone's tmp/ belongs there too: the
  # fallback reads it by the same rule as the root's own tmp/.
  mkdir -p "$root/base/.git/worktrees/wt" "$root/base/tmp" "$root/wt"
  printf 'gitdir: %s\n' "$root/base/.git/worktrees/wt" > "$root/wt/.git"
  printf '%s\n' "$root/wt/.git" > "$root/base/.git/worktrees/wt/gitdir"
  printf 'project: DX\n' > "$root/base/tmp/.workitems.plane.yml"

  local before after
  before="$(manifest "$root")"
  bash "$RESOLVE" --repo-root "$root/single" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/multi" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/bare" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/single" --tracker github >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/single" --tracker linear >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/absent" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/wt" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/wt" --with-config-path >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/wt" --tracker plane --with-config-path >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/single" --with-config-path >/dev/null 2>&1 || true
  bash "$RESOLVE" --help >/dev/null 2>&1 || true
  after="$(manifest "$root")"

  [ "$before" = "$after" ]
}
