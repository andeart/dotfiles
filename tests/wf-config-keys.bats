#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

# Each wf-* skill's "The keys this skill reads:" list is the halt check's input:
# the skill confirms every key in it is present in the resolver's dump and stops
# on any that is <unset>. A typo in that list fails nowhere and never clears -
# `states.in_review` matches no dump line, so the skill reports it unset on
# every run, and /wf-config cannot fill it because it is not a key. Extracting a
# list out of markdown has two precedents here already, in
# tests/wf-review-check-state.bats and tests/wf-wrap-gh-jq.bats.

# The five skills that halt. wf-wrap reads one key and never halts - by its
# Step 6 the worktree is gone - so it carries no list; wf-prune reads none.
HALTING_SKILLS=(wf-ship wf-status wf-shape wf-spec-review wf-impl-review)

# known_shapes: KNOWN_SHAPES one per line, read from the script rather than
# copied - a copy would grade a stale list and pass while the real one moved.
known_shapes() {
  bash -c '_WF_LIB_ONLY=1 source "$0"; printf "%s\n" "${KNOWN_SHAPES[@]}"' "$RESOLVE"
}

# key_list <file>: the bullet lines under "The keys this skill reads:", ending
# at the first blank line after the list rather than at the first blank line -
# the anchor's own paragraph break sits between the two.
key_list() {
  awk '
    /^The keys this skill reads:/ { inlist = 1; next }
    inlist && /^- / { print; seen = 1; next }
    inlist && seen && /^[[:space:]]*$/ { exit }
    inlist && /^[[:space:]]*$/ { next }
    inlist { exit }
  ' "$1"
}

# dotted_keys <file>: every dotted wf key the list names, with a trailing index
# normalised to .N - shape_of's own rule, applied to markdown. Without it
# `review.reviewers.1` fails to match `review.reviewers.N` and the test fails on
# correct input.
#
# Only a whole backticked span counts, anchored: a bare `.2` continuation and a
# backticked filename like `.wf.yml` both start with a dot and are excluded,
# where an unanchored search would pull `wf.yml` out of the second and fail on
# correct input. Every segment but a trailing index starts with a letter, and
# `_` is in the class on purpose - `states.in_review` is exactly the typo this
# test exists to catch, so it has to reach the lookup below rather than be
# filtered out as noise. The `=` trim keeps a span written as a dump line,
# `verify.commands=<none>`, naming its key.
dotted_keys() {
  key_list "$1" \
    | grep -o '`[^`]*`' \
    | tr -d '`' \
    | sed 's/=.*//' \
    | grep -E '^[a-z][a-z_-]*(\.[a-z][a-z0-9_-]*)+(\.[0-9]+)?$' \
    | sed 's/\.[0-9][0-9]*$/.N/' \
    | sort -u || true
}

# knows <shapes> <key>: whether the resolver understands that key. A list key
# reaches a skill's prose both ways - `verify.commands.1` for a member and
# `verify.commands` for the whole key, which is what the dump's <none> and
# <unset> lines carry - so both spell the same KNOWN_SHAPES entry.
knows() {
  printf '%s\n' "$1" | grep -qxF "$2" || printf '%s\n' "$1" | grep -qxF "$2.N"
}

@test "every halting skill carries a key list" {
  local skill file
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    [ -f "$file" ]
    # A skill without a list halts on nothing and is pinned by nothing.
    if [ -z "$(key_list "$file")" ]; then
      echo "$skill has no 'The keys this skill reads:' list" >&2
      return 1
    fi
  done
}

@test "every key a skill's list names is a key the resolver knows" {
  local shapes skill file key
  shapes="$(known_shapes)"
  [ -n "$shapes" ]
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    while IFS= read -r key; do
      [ -n "$key" ] || continue
      if ! knows "$shapes" "$key"; then
        echo "$skill names $key, which is not in KNOWN_SHAPES" >&2
        return 1
      fi
    done <<EOF
$(dotted_keys "$file")
EOF
  done
}

# The other direction: a key nobody reads is a key nobody can be halted on, so
# it would sit in KNOWN_SHAPES and in the template with no consumer. wf-wrap
# reads wrap.watch-post-merge-ci without carrying a list, so it is named here
# rather than extracted.
@test "every key in KNOWN_SHAPES is read by some skill" {
  local claimed skill shape
  claimed="wrap.watch-post-merge-ci"
  for skill in "${HALTING_SKILLS[@]}"; do
    claimed="$claimed
$(dotted_keys "$DOTFILES_ROOT/agents/skills/$skill/SKILL.md")"
  done
  while IFS= read -r shape; do
    [ -n "$shape" ] || continue
    if ! printf '%s\n' "$claimed" | grep -qxF "$shape"; then
      echo "$shape is in KNOWN_SHAPES but no skill's key list names it" >&2
      return 1
    fi
  done <<EOF
$(known_shapes)
EOF
}
