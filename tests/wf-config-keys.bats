#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

# Each wf-* skill names the config keys it reads twice: once in prose, under
# "The keys this skill reads:", and once as the resolver's `--require`
# argument. The prose says what each key is for; the argument is what actually
# halts the run. This pins them to each other and both to KNOWN_SHAPES.
#
# The two drifting apart is the failure worth catching. A key dropped from
# --require but left in the prose reads as required and is not; one added to
# --require but left out of the prose halts a run for a reason the skill never
# documents. Extracting a list out of markdown has two precedents here already,
# in tests/wf-review-check-state.bats and tests/wf-wrap-gh-jq.bats.

# Every skill that reads config. wf-wrap is here for its prose list only: it
# passes no --require, which tests/wf-config-halt-check.bats pins separately.
CONFIG_SKILLS=(wf-ship wf-status wf-shape wf-spec-review wf-impl-review wf-wrap)
HALTING_SKILLS=(wf-ship wf-status wf-shape wf-spec-review wf-impl-review)

# The readers that are not skills. A hook carries the same "The keys this hook
# reads:" list a skill does, so the extraction below covers both and a key read
# only from here still counts as read.
CONFIG_HOOKS=(copy-into-worktree)

# config_readers: every reader's file, one path per line.
config_readers() {
  local name
  for name in "${CONFIG_SKILLS[@]}"; do
    printf '%s\n' "$DOTFILES_ROOT/agents/skills/$name/SKILL.md"
  done
  for name in "${CONFIG_HOOKS[@]}"; do
    printf '%s\n' "$DOTFILES_ROOT/claude/hooks/$name.sh"
  done
}

# known_shapes: KNOWN_SHAPES one per line, read from the script rather than
# copied - a copy would grade a stale list and pass while the real one moved.
known_shapes() {
  bash -c '_WF_LIB_ONLY=1 source "$0"; printf "%s\n" "${KNOWN_SHAPES[@]}"' "$RESOLVE"
}

# key_list <file>: the bullet lines under "The keys this skill reads:", ending
# at the first blank line after the list rather than at the first blank line -
# the anchor's own paragraph break sits between the two.
#
# The sed strips a shell comment marker so one extraction covers a SKILL.md and
# a hook script both. It runs on markdown too, where it can only touch a
# heading: no heading is the anchor, and a heading after the list ends it at
# `inlist { exit }` whether or not its `#` survived.
key_list() {
  sed 's/^#[[:space:]]\{0,1\}//' "$1" | awk '
    /^The keys this (skill|hook) reads:/ { inlist = 1; next }
    inlist && /^- / { print; seen = 1; next }
    inlist && seen && /^[[:space:]]*$/ { exit }
    inlist && /^[[:space:]]*$/ { next }
    inlist { exit }
  '
}

# prose_keys <file>: every dotted wf key the bullet list names, with a trailing
# index dropped so a member spells its list. Without that `review.reviewers.1`
# would not match the `review.reviewers` the --require list carries.
#
# Only a whole backticked span counts, anchored: a bare `.2` continuation and a
# backticked filename like `.wf.yml` both start with a dot and are excluded,
# where an unanchored search would pull `wf.yml` out of the second and fail on
# correct input. Every segment but a trailing index starts with a letter, and
# `_` is in the class on purpose - `states.in_review` is exactly the typo this
# test exists to catch, so it has to reach the comparison rather than be
# filtered out as noise. The `=` trim keeps a span written as a dump line,
# `verify.commands=<none>`, naming its key.
prose_keys() {
  key_list "$1" \
    | grep -o '`[^`]*`' \
    | tr -d '`' \
    | sed 's/=.*//' \
    | grep -E '^[a-z][a-z_-]*(\.[a-z][a-z0-9_-]*)+(\.[0-9]+)?$' \
    | sed 's/\.[0-9][0-9]*$//' \
    | sort -u
}

# require_keys <file>: the --require argument, one key per line. Anchored at the
# start of a continuation line so the prose mentioning `--require` in backticks
# cannot match.
require_keys() {
  sed -n 's/^[[:space:]]*--require \([a-z0-9.,_-]*\).*$/\1/p' "$1" \
    | tr ',' '\n' \
    | sed 's/\.[0-9][0-9]*$//' \
    | grep -v '^$' \
    | sort -u
}

@test "every reader of the config carries a prose key list" {
  local file
  while IFS= read -r file; do
    [ -f "$file" ]
    if [ -z "$(key_list "$file")" ]; then
      echo "$file has no 'The keys this ... reads:' list" >&2
      return 1
    fi
  done <<EOF
$(config_readers)
EOF
}

# The cross-check. Either list alone can be wrong; disagreeing is what proves it.
@test "each halting skill's --require list matches its prose list" {
  local skill file
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    if ! diff <(prose_keys "$file") <(require_keys "$file") >/dev/null; then
      echo "$skill's prose list and --require list disagree (< prose, > --require):" >&2
      diff <(prose_keys "$file") <(require_keys "$file") >&2 || true
      return 1
    fi
  done
}

@test "every key a reader's prose names is a key the resolver knows" {
  local shapes file key
  shapes="$(known_shapes | sed 's/\.N$//' | sort -u)"
  [ -n "$shapes" ]
  while IFS= read -r file; do
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      if ! printf '%s\n' "$shapes" | grep -qxF "$key"; then
        echo "$file names $key, which is not in KNOWN_SHAPES" >&2
        return 1
      fi
    done <<EOF
$(prose_keys "$file")
EOF
  done <<EOF
$(config_readers)
EOF
}

# The other direction: a key nobody reads is a key nobody can be halted on, so
# it would sit in KNOWN_SHAPES and in the template with no consumer. Every
# claim is extracted, including wf-wrap's and the hooks' - a literal here would
# need updating by hand the day one of them reads a second key, which is the
# drift this file exists to catch.
@test "every key in KNOWN_SHAPES is read by some reader" {
  local claimed="" file shape
  while IFS= read -r file; do
    claimed="$claimed
$(prose_keys "$file")"
  done <<EOF
$(config_readers)
EOF
  while IFS= read -r shape; do
    [ -n "$shape" ] || continue
    if ! printf '%s\n' "$claimed" | grep -qxF "$shape"; then
      echo "$shape is in KNOWN_SHAPES but no reader's key list names it" >&2
      return 1
    fi
  done <<EOF
$(known_shapes | sed 's/\.N$//')
EOF
}

# A hook has no user to send to /wf-config and runs where a nonzero exit fails a
# tool call, so it must never pass --require. wf-wrap is held to the same rule
# in tests/wf-config-halt-check.bats; this is that rule for the hooks.
@test "no config-reading hook passes --require" {
  local name file
  for name in "${CONFIG_HOOKS[@]}"; do
    file="$DOTFILES_ROOT/claude/hooks/$name.sh"
    [ -f "$file" ]
    if [ -n "$(require_keys "$file")" ]; then
      echo "$name passes --require; a hook must fail open, not halt" >&2
      return 1
    fi
  done
}
