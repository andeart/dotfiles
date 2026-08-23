#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/work-item-conventions/scripts/resolve-tracker.sh"
REFERENCES="$DOTFILES_ROOT/agents/skills/work-item-conventions/references"
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

# A value that looks like a regex is still just a value: is_known_tracker matches
# with a quoted `case` pattern and the candidate match uses `grep -qxF`, so
# neither reads it as one. Unguarded, the run would exit 0 naming a tracker with
# no reference file behind it.
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

# Interior whitespace is left in place so the value stays malformed and gets
# rejected downstream, rather than being repaired into a name that resolves.
@test "declared_default trims surrounding whitespace but keeps interior" {
  local root; root="$(repo dd-interior)"
  config "$root" plane "default_tracker:   git hub   "
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "git hub" ]
}

# Interior quotes go the same way interior whitespace does: left alone, so the
# value stays malformed and is rejected downstream instead of being repaired
# into a name that resolves.
@test "declared_default strips surrounding quotes but keeps interior ones" {
  local root; root="$(repo dd-inner-quotes)"
  config "$root" plane 'default_tracker: gi"th"ub'
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = 'gi"th"ub' ]
}

# Whitespace has to come off before the quote run, or `"github"   ` is trimmed
# to `github"` - a quote the value never meant to carry.
@test "declared_default strips a quoted value padded with trailing whitespace" {
  local root; root="$(repo dd-quoted-padded)"
  config "$root" plane 'default_tracker: "github"   '
  call declared_default "$root/.workitems.plane.yml"
  [ "$output" = "github" ]
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

# file-work-item reads `<tracker>-creating.md` alongside the main reference, and
# tells a run that a skeleton has none beside it. Both halves have to hold of
# what is actually on disk, or one of those instructions sends a run at a file
# that isn't there.
@test "a create-side reference sits beside every reference that is not a skeleton" {
  call known_trackers
  local t main creating
  for t in $output; do
    main="$REFERENCES/$t.md"
    creating="$REFERENCES/$t-creating.md"
    if grep -q '^\*\*This reference is a skeleton' "$main"; then
      [ ! -e "$creating" ] || {
        echo "$t.md is a skeleton but $t-creating.md exists beside it" >&2
        return 1
      }
    else
      [ -f "$creating" ] || {
        echo "$t.md is implemented but $t-creating.md is missing" >&2
        return 1
      }
    fi
  done
}

# ─── the two readers of the same file agree ────────────────────────────────

# resolve-tracker.sh and gh-set-default-settings both read top-level scalars out
# of a .workitems.plane.yml with their own not-a-YAML-parser. They drifted once
# already (one deleted interior whitespace, the other kept it), and the drift is
# invisible until a value lands in the wrong tracker, so pin them together.
@test "declared_default and plane_config_value read the same value the same way" {
  local root; root="$(repo parser-agreement)"
  local file="$root/.workitems.plane.yml"
  local v a b
  for v in 'github' '"github"' "'github'" '"github"   ' '  github  ' 'gi"th"ub' \
           '"github"  # note' 'git hub' 'p.ane' '.*' '"gith ub" ' 'github#x'; do
    printf 'default_tracker: %s\n' "$v" > "$file"
    a="$(bash -c '_WORKITEMS_LIB_ONLY=1 source "$1"; declared_default "$2"' _ "$RESOLVE" "$file")"
    b="$(bash -c '_GH_SETTINGS_LIB_ONLY=1 source "$1"; plane_config_value "$2" default_tracker' _ "$GH_SETTINGS" "$file")"
    [ "$a" = "$b" ] || {
      echo "disagree on [$v]: declared_default=[$a] plane_config_value=[$b]" >&2
      return 1
    }
  done
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

# The script header promises it only ever reads, and that promise is the whole
# case for putting it on a permission allowlist. Every branch runs here,
# including the ones that exit non-zero - an error path is where a stray write
# is likeliest and least noticed.
@test "resolving never writes to the tree it reads" {
  local root; root="$(repo read-only)"
  mkdir -p "$root/single/tmp" "$root/multi" "$root/bare"
  printf 'project: DX\n' > "$root/single/tmp/.workitems.plane.yml"
  printf 'default_tracker: p.ane\n' > "$root/multi/.workitems.plane.yml"
  printf 'assignee: octocat\n' > "$root/multi/.workitems.github.yml"

  local before after
  before="$(manifest "$root")"
  bash "$RESOLVE" --repo-root "$root/single" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/multi" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/bare" >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/single" --tracker github >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/single" --tracker linear >/dev/null 2>&1 || true
  bash "$RESOLVE" --repo-root "$root/absent" >/dev/null 2>&1 || true
  bash "$RESOLVE" --help >/dev/null 2>&1 || true
  after="$(manifest "$root")"

  [ "$before" = "$after" ]
}
