#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# Skills under agents/skills/ deploy to ~/.claude/skills and ~/.agents/skills,
# so "this repo" inside one resolves to whichever repo the agent is standing
# in. A skill that runs a check and then states its answer leaves the agent no
# reason to run it, so the mechanism goes unused and the wrong branch is taken.
#
# AGENTS.md carries the rule and reaches phrasings a grep never will; this file
# catches the ones already written. Both are asserted below - without that, the
# rule can be deleted while the list stays green.
#
# The glob is every skill rather than wf-*: a test narrower than the rule it
# enforces drifts from it.

# Literals, matched with grep -F. An entry earns its place by having been seen
# in a real skill, not by being a phrasing someone might write. Each must be
# long enough to be unique to its sentence: a short entry flags the conditional
# phrasings the rule allows, and then a correct skill cannot be written.
#
# Two shapes are banned. Most entries name a repo outright. The last one names
# none and is still an answer handed to the agent - a claim widened to cover
# every merge method, which measurement contradicts for two of the three.
BANNED=(
  'gitignored here'
  'so it is always `no` here'
  'Merges here are squashes'
  'A squash merge guarantees this'
  'in the psychfam repos'
  'in every repo this family runs in'
  'which is correct under all three'
)

# The negative control, and the only thing holding the line the comment above
# draws: correctly phrased prose, taken from the skills it actually lives in
# rather than invented here, that the list must not match. Shorten an entry
# until it reaches conditional phrasing and this goes red before a correct
# skill becomes unwritable - `gitignored here` down to `gitignor` trips the
# first two, and down to `here` trips the third.
#
# The third is a fragment rather than its whole sentence only because that
# sentence carries an apostrophe. Each has to be a literal substring of a
# skill, which the case below re-checks.
CONTROL=(
  'A repo that gitignores all of `docs/` answers `no`'
  'A repo that gitignores all of `docs/` can never produce a docs-only push'
  'not a special case here'
)

# The two clauses the AGENTS.md rule cannot lose and still be the same rule:
# the ban itself, and the half reaching a claim widened out of one repo into
# all of them. A sentence can satisfy the first and break the second, which is
# why both are anchored. Reword freely around them.
RULE_ANCHORS=(
  'it must never say "the answer is Y"'
  'Widening a repo-specific claim into a universal one'
)

@test "the banned-phrase list is not empty" {
  # An emptied list would make the sweep below pass over anything at all.
  [ "${#BANNED[@]}" -gt 0 ]
}

@test "the skills glob names real files" {
  assert_skill_glob
}

@test "no skill states the answer to a check the repo decides" {
  # One grep over every phrase and every file, rather than one per pair: the
  # list is meant to grow an entry per real incident, and grep's own
  # `file:line:` prefix already names what a per-pair failure message would
  # have had to assemble.
  local phrase f pats=() files=() hits
  for phrase in "${BANNED[@]}"; do
    pats+=(-e "$phrase")
  done
  while IFS= read -r f; do
    files+=("$f")
  done < <(skill_files)

  hits="$(grep -n -F "${pats[@]}" -- "${files[@]}" || true)"
  [ -z "$hits" ] || fail "$(printf 'A skill states an answer the repo decides:\n%s\n\nA skill may say "if the repo does X, the answer is Y". It may not say "the answer is Y" - state the rule and let the check answer. See the rule in AGENTS.md.' "${hits//$DOTFILES_ROOT\//}")"
}

@test "a correctly phrased conditional does not trip the list" {
  local phrase f sentence pats=() files=()
  for phrase in "${BANNED[@]}"; do
    pats+=(-e "$phrase")
  done
  while IFS= read -r f; do
    files+=("$f")
  done < <(skill_files)

  for sentence in "${CONTROL[@]}"; do
    # A control that drifted out of the skills would grade nothing, so it has
    # to still be a real sentence in a real one.
    grep -F -e "$sentence" -- "${files[@]}" > /dev/null \
      || fail "the control sentence is no longer in any skill: $sentence"
    if printf '%s\n' "$sentence" | grep -F "${pats[@]}" > /dev/null; then
      fail "the banned list matches a correctly phrased conditional: $sentence"
    fi
  done
}

@test "AGENTS.md still carries the written rule" {
  # The written rule and the phrase list are complements: the list catches the
  # wordings already used, the rule reaches the ones nobody has written yet.
  # Without this the rule can be deleted while the list stays green, leaving
  # one half of a pair doing the work of both.
  local anchor
  for anchor in "${RULE_ANCHORS[@]}"; do
    grep -n -F -e "$anchor" "$DOTFILES_ROOT/AGENTS.md" > /dev/null \
      || fail "AGENTS.md no longer carries the repo-dependent-claims rule: $anchor"
  done
}
