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
  # Called directly rather than through the `call` harness, which reads a return
  # value out of stdout: this assigns and prints nothing, so the assignment has
  # to be echoed from the same shell that made it.
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

# Decision 4: the lookups assign and print nothing, which is what deletes five
# command substitutions per sweep - four inside discover_trackers' loop and the
# one that used to read the loop back. A caller that goes back to $() gives the
# whole saving away, so both halves are pinned: the value is right, and it
# survives being read from the calling shell rather than a subshell.
@test "config_path_for assigns CONFIG_PATH and prints nothing" {
  local root; root="$(repo assigns-config-path)"
  config "$root" plane
  # Two calls, and the reason is the point: the $() one runs the function in a
  # subshell that takes the assignment away with it, which is exactly what the
  # callers inside the script stopped doing.
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

# A sweep calls this once per tracker in turn, so a value left behind by the
# previous tracker would report every tracker as configured.
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

# The other half of the same saving, and the larger one: a sweep read back
# through $() pays a subshell for the loop on top of the four inside it.
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

# worktree <name>: a linked-worktree pair built the way git writes one - a .git
# file naming the registration, and the registration's own gitdir naming this
# worktree back. Sets $BASE and $WT. No git init, keeping this suite's
# filesystem-only invariant: the back-reference is the whole of what the
# resolver verifies, and a fixture of plain directories would skip exactly that.
worktree() {
  BASE="$BATS_TEST_TMPDIR/$1/base"
  WT="$BATS_TEST_TMPDIR/$1/wt"
  local reg="$BASE/.git/worktrees/$1"
  mkdir -p "$reg" "$WT"
  printf 'gitdir: %s\n' "$reg" > "$WT/.git"
  printf '%s\n' "$WT/.git" > "$reg/gitdir"
}

# physical <dir>: <dir> with `..` and every symlink resolved, which is the form
# base_clone prints an inherited path in. Asserting against a literal $BASE
# would pass on Linux and fail on macOS, where BATS_TEST_TMPDIR sits under a
# symlinked /var. A root's own path is used verbatim and is not wrapped.
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

# Decision 3, and the case the rejected per-tracker fallback fails: it would
# report both trackers and send a repo that resolves cleanly today to an ask.
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

# The base clone is read by config_path_for's own rule, tmp/ included: tmp/ is
# where a config that should not sit in a public tree goes, gitignored is what
# stops a file travelling into a worktree, so tmp/ holds the configs likeliest
# to need this fallback.
@test "the base clone's tmp/ copy is consulted" {
  worktree base-tmp
  mkdir -p "$BASE/tmp"
  printf '\n' > "$BASE/tmp/.workitems.jira.yml"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "jira" ]
}

# The trust boundary, graded through this script rather than through base_clone
# in isolation. The neighbour carries a config, so a run that skipped the
# back-reference check would resolve `plane` instead of asking.
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

# An ordinary clone has a .git directory, so the hoisted is-a-file test declines
# before base_clone is ever forked.
@test "an ordinary clone with a .git directory resolves without a fallback" {
  local root; root="$(repo ordinary-clone)"
  mkdir -p "$root/.git"
  config "$root" plane
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$output" = "plane" ]
}

# ─── --with-config-path ────────────────────────────────────────────────────

# The skills that resolve a tracker go on to read that tracker's config, so the
# path rides along on the call already being made rather than costing a second
# fork - and, behind it, a whole model round trip.

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

# /wf-ship's own invocation, and the only case that exercises the explicit
# branch and the search root together - the pair the explicit branch returns
# before ever reaching without the flag.
@test "--tracker with --with-config-path reaches the base clone from a worktree" {
  worktree path-explicit-inherits
  config "$BASE" plane
  resolve "$WT" --tracker plane --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "plane" ]
  [ "$(key config_path)" = "$(physical "$BASE")/.workitems.plane.yml" ]
}

# The contract /wf-ship branches on to reach its "no config exists" arm. Empty
# is a real answer rather than an ambiguity, because the root was validated.
@test "--tracker with --with-config-path prints an empty path when that tracker has no config" {
  local root; root="$(repo path-explicit-none)"
  config "$root" plane
  resolve "$root" --tracker github --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key tracker)" = "github" ]
  [ "$(key config_path)" = "" ]
  [[ "$output" == *"config_path="* ]]
}

# Decision 3 applied consistently: the search root is decided by whether the
# root carries any config, not this one, so a worktree with a config of its own
# reports an empty path for another tracker rather than reaching next door.
@test "a worktree with its own config reports an empty path for a tracker only the base clone has" {
  worktree path-no-mixing
  config "$WT" github
  config "$BASE" plane
  resolve "$WT" --tracker plane --with-config-path
  [ "$status" -eq 0 ]
  [ "$(key config_path)" = "" ]
}

# Validated before it reaches a path: $tracker is interpolated straight into
# $root/.workitems.$tracker.yml, so the ordering is the guarantee.
@test "--with-config-path with an unknown tracker exits 2" {
  local root; root="$(repo path-unknown-tracker)"
  config "$root" plane
  resolve "$root" --tracker linear --with-config-path
  [ "$status" -eq 2 ]
  [ -z "$output" ]
}

# A nonexistent root printing an empty path is the one answer a caller cannot
# tell apart from a repo that genuinely has no config, so the flag imposes the
# check the explicit branch deliberately goes without.
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

# The asymmetry Design 2 describes. The four stderr messages are prose a reader
# takes as one line; config_path= is a field a skill reads by name, where a
# newline in a directory name forges another one.
@test "a root carrying a control character exits 2 under --with-config-path" {
  local root="$BATS_TEST_TMPDIR/ctrl"$'\n'"x"
  mkdir -p "$root"
  config "$root" plane
  resolve "$root" --with-config-path
  [ "$status" -eq 2 ]
  [[ "$output" != *"config_path="* ]]
}

# The message names the flag, never the value. Interpolating the path would move
# the forgery from stdout to stderr rather than stopping it: file-work-item reads
# exit 2 as "stop and show it", so a root named `<dir>\nconfig_path=/etc/passwd`
# would reach the user as a config_path= line the run had just refused to print.
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

# count_sweeps <root> [args...]: how many times one run calls config_path_for,
# through a stub that counts and delegates. Sets $SWEEPS.
count_sweeps() {
  local root="$1"; shift
  local counter="$BATS_TEST_TMPDIR/sweeps"
  : > "$counter"
  run bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"
    eval "orig_$(declare -f config_path_for)"
    COUNTER="$3"
    config_path_for() { printf "x\n" >> "$COUNTER"; orig_config_path_for "$@"; }
    root="$2"; shift 3
    resolve "$root" "$@"' _ "$RESOLVE" "$root" "$counter" "$@"
  SWEEPS="$(grep -c . "$counter")"
}

# Decision 4's shape, pinned rather than asserted in a document nothing
# re-reads: reading the search root, the candidates and the config path back
# through separate command substitutions is three sweeps of a loop that was five
# forks before it assigned, and that shape is one refactor away.
#
# An upper bound rather than an equality. What must not come back is a sweep the
# run does not need; a later change that answers in fewer is an improvement, and
# a test that fails on it would be arguing for the cost it exists to prevent.
@test "a detection run with --with-config-path sweeps once in an ordinary clone" {
  local root; root="$(repo sweeps-clone)"
  config "$root" plane
  count_sweeps "$root" "" yes
  [ "$status" -eq 0 ]
  # Four trackers for the one sweep, plus emit_answer's single lookup. A second
  # sweep would be 9, a third 13.
  [ "$SWEEPS" -le 5 ]
}

@test "a detection run with --with-config-path sweeps twice in an inheriting worktree" {
  worktree sweeps-worktree
  config "$BASE" plane
  count_sweeps "$WT" "" yes
  [ "$status" -eq 0 ]
  # The worktree's own sweep, the base clone's, and emit_answer's lookup. Never
  # a third sweep, which would be 13.
  [ "$SWEEPS" -le 9 ]
}

# unique_lines dedupes and counts in the shell rather than through a
# `sort -u | grep .` pipeline and a `grep -c .` one - the same fork class
# decision 4 removed from config_path_for, on the branch the base clone fallback
# newly routes worktrees onto.
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

# First-occurrence order rather than `sort -u`'s alphabetical one, so the
# disagreement message below lists the defaults in the order the candidates
# print above it. Pinned because it is the one observable the swap changed.
@test "the disagreement message lists defaults in candidate order" {
  local root; root="$(repo declared-order)"
  config "$root" plane 'default_tracker: github'
  config "$root" github 'default_tracker: plane'
  resolve "$root"
  [ "$status" -eq 10 ]
  [[ "$stderr" == *"disagree on default_tracker: github plane"* ]]
}

# has_line replaces `grep -qxF`, and -F is the half that matters: a
# default_tracker value is file content, so a `*` in it must match literally
# rather than against every candidate. A partial line never matches either.
#
# The multi-line value matches, because a run of whole lines is what it is. That
# differs from `grep -qxF`, which would have matched on any one of them - and
# neither behaviour is reachable, because resolve() only calls this once
# n_declared is 1. Asserted rather than left undefined so the divergence is on
# the record instead of being rediscovered.
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

# The reason unique_lines peels one line at a time instead of splitting on IFS: a
# default_tracker value is file content and reaches it unquoted under a split, so
# `*` would expand against the working directory and count the files there. The
# fixture directory holds two configs, so a globbing count would not be 1 and the
# run would take a different exit-10 branch than the one asserted here.
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

# Decision 10, and the reason the guard is an explicit [ -f ] rather than the
# source's own failure: `set -euo pipefail; . /nonexistent` exits 1, with bash's
# message naming the path but not the script. A broken install is not a usage
# error the caller can fix by changing arguments, but 2 is what "this
# invocation cannot proceed for an environment reason" already means here.
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

# Invoked from its own directory the script's $0 carries no slash, where a bare
# `${BASH_SOURCE[0]%/*}` yields the script's own name rather than `.` - which
# sent the guard above off a path that cannot exist and told a user with a
# complete install to run `dotfiles push`. Debugging the script from beside it
# is the one thing that reaches this.
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

# The script's shebang resolves to bash 5.x on this machine's PATH, so a passing
# `bash -n` proves nothing about macOS's shipped /bin/bash 3.2 - only running the
# parser under 3.2 itself does. CI runs Ubuntu, where /bin/bash is already 5.x,
# so skip there rather than pass trivially.
@test "the script parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$RESOLVE"
  [ "$status" -eq 0 ]
}

# ${BASH_SOURCE[0]} makes bash part of the library-mode contract, and both this
# script's sourced callers honour it. A SKILL.md block runs in zsh but forks
# this rather than sourcing it, which this run is.
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

  # The base clone arm is the first branch that reaches outside --repo-root, and
  # this guarantee is what RESOLUTION.md cites for the allowlist claim, so the
  # pair belongs inside the manifest rather than beside it. The base clone's
  # tmp/ too, which the fallback reads by the same rule as the root's own.
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
