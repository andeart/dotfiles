#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"
TEMPLATE="$DOTFILES_ROOT/agents/skills/wf-conventions/wf.yml.template"

# /wf-config dispatches on `yq 'tag'` and fills with `yq ea 'select(fi==0) *
# select(fi==1)'`. Every row of its decision table and every promise its
# "Filling an existing file" section makes is a claim about how this yq behaves,
# and the skill is prose: nothing fails when one stops being true. A yq that
# starts reporting a comments-only file as !!map, or an `ea` that merges a
# shorter list by index, would silently route the skill down the wrong branch or
# quietly replace a value the user chose.
#
# So this pins the yq behaviours the skill depends on, not the skill's wording.
# A failure here means the table in wf-config/SKILL.md needs rewriting, not that
# the test is wrong.

setup() {
  command -v yq >/dev/null 2>&1 || skip "yq is not installed"
}

# doc <name> <body>: write a YAML document and print its path.
doc() {
  local f="$BATS_TEST_TMPDIR/$1.yml"
  printf '%s' "$2" > "$f"
  printf '%s\n' "$f"
}

# ─── the dispatch table ────────────────────────────────────────────────────

# Rows "!!null" (zero-byte) and "!!null" (comments only) both route to "Writing
# a new file": there is nothing for the merge to fill, and `select(fi==1)`
# would select nothing and emit zero bytes at exit 0.
@test "an empty file tags as !!null" {
  run yq 'tag' "$(doc empty '')"
  [ "$status" -eq 0 ]
  [ "$output" = '!!null' ]
}

@test "a comments-only file tags as !!null" {
  run yq 'tag' "$(doc comments '# just a comment
# and another
')"
  [ "$status" -eq 0 ]
  [ "$output" = '!!null' ]
}

# Routes to "Writing a new file" as well: a root-level {} does merge, but into
# flow style, so the copy path is what hands back a readable file.
@test "a root-level empty map tags as !!map" {
  run yq 'tag' "$(doc flow '{}
')"
  [ "$status" -eq 0 ]
  [ "$output" = '!!map' ]
}

@test "a real mapping tags as !!map" {
  run yq 'tag' "$(doc real 'states:
  shaping: Shaping
')"
  [ "$status" -eq 0 ]
  [ "$output" = '!!map' ]
}

# Stops the skill. A bare scalar reaches the resolver at exit 0 with every key
# <unset>, because read_props drops any props line without a " = " separator -
# so it arrives looking like an ordinary incomplete file, and the merge then
# fails with "cannot multiply !!map with !!str".
@test "a root-level scalar tags as !!str" {
  run yq 'tag' "$(doc scalar 'hello
')"
  [ "$status" -eq 0 ]
  [ "$output" = '!!str' ]
}

# Stops the skill. The table's rows are single values, so "more than one line"
# is what identifies a multi-document file - it matches no row.
@test "a multi-document file tags once per document" {
  run yq 'tag' "$(doc multi 'a: 1
---
b: 2
')"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 2 ]
}

# The table never sees a root-level list: the resolver rejects it first. It used
# to report `unknown key: 0`, naming an index the file never spelled.
@test "a root-level list is rejected by the resolver before the table" {
  local root="$BATS_TEST_TMPDIR/rootlist"
  mkdir -p "$root"
  printf '[a, b]\n' > "$root/.wf.yml"
  run --separate-stderr bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"the document's root is a list"* ]]
}

# ─── the fill's promise ────────────────────────────────────────────────────

# fill <root>: the exact command "Filling an existing file" runs.
fill() {
  local root="$1" tmp
  tmp="$(mktemp)"
  cp -p "$root/.wf.yml" "$tmp" \
    && yq ea 'select(fi==0) * select(fi==1)' "$TEMPLATE" "$root/.wf.yml" > "$tmp" \
    && mv "$tmp" "$root/.wf.yml"
}

# partial <name>: a repo whose .wf.yml declares a couple of keys and its own
# values for them, and prints the root.
partial() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  printf '# my own header\nstates:\n  shaping: Triage\nreview:\n  reviewers:\n    - Solo\n' \
    > "$root/.wf.yml"
  printf '%s\n' "$root"
}

# The one thing the fill path exists to promise.
@test "the fill keeps every value the file already declared" {
  local root; root="$(partial keeps)"
  fill "$root"
  run bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"states.shaping=Triage"* ]]
}

# A shorter list replaces the template's outright rather than merging by index,
# which is the same rule the resolver applies to a list it reads.
@test "the fill does not merge a shorter list by index" {
  local root; root="$(partial roster)"
  fill "$root"
  run bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review.reviewers.1=Solo"* ]]
  [[ "$output" != *"review.reviewers.2="* ]]
}

@test "the fill supplies every key the file left out" {
  local root; root="$(partial complete)"
  fill "$root"
  run bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 0 ]
  [[ "$output" != *"<unset>"* ]]
}

@test "the filled file still satisfies every key in KNOWN_SHAPES" {
  local root shapes keys
  root="$(partial required)"
  fill "$root"
  shapes="$(bash -c '_WF_LIB_ONLY=1 source "$0"; printf "%s\n" "${KNOWN_SHAPES[@]}"' "$RESOLVE")"
  keys="$(printf '%s\n' "$shapes" | sed 's/\.N$//' | paste -sd, -)"
  run bash "$RESOLVE" --repo-root "$root" --require "$keys"
  [ "$status" -eq 0 ]
}

# mode_of <file>: the permission string, via ls rather than stat. BSD stat
# takes -f and GNU stat reads that as "file system", so a stat spelling that
# passes here fails on the Ubuntu runner. GNU ls appends a `.` or `+` for
# SELinux and ACLs, which the trim drops.
mode_of() {
  ls -l "$1" | awk '{ print substr($1, 1, 10) }'
}

# git tracks no mode but the exec bit, so a mode the fill changed would never
# show in a diff or a `git status`. The cp -p is what carries it across; a
# hard-coded chmod would be wrong in one direction or the other.
@test "the fill preserves a 644 config's mode" {
  local root; root="$(partial mode644)"
  chmod 644 "$root/.wf.yml"
  fill "$root"
  [ "$(mode_of "$root/.wf.yml")" = '-rw-r--r--' ]
}

@test "the fill preserves a deliberately narrowed 600 config's mode" {
  local root; root="$(partial mode600)"
  chmod 600 "$root/.wf.yml"
  fill "$root"
  [ "$(mode_of "$root/.wf.yml")" = '-rw-------' ]
}
