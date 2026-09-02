#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# The halt check - check every key in the skill's list against the resolver's
# dump, stop on one that is <unset>, and collapse the wording when the file
# itself is absent - is one contract applied by five skills, so all five carry
# the same paragraphs. Nothing enforced that: it is thirteen lines of prose in
# five files, and a wording change to one is invisible until a skill halts
# differently from its neighbours. This extracts every copy straight out of the
# markdown and pins them against each other, the same way
# tests/wf-review-check-state.bats pins the check-state block across the two
# review skills and tests/wf-wrap-gh-jq.bats pins a jq program against the
# SKILL.md it still lives in.
#
# It is deliberately not the same test as tests/wf-config-keys.bats: that one
# pins each skill's key list against KNOWN_SHAPES, which is the halt check's
# input. This pins the check that consumes it.

HALTING_SKILLS=(wf-ship wf-status wf-shape wf-spec-review wf-impl-review)

# halt_block <file>: the sync note through the closing <none> line. Those two
# lines are the extraction anchors, so rewording either one empties the block
# here even though the prose is still present - the first test below says so
# when it fires. The one per-skill line - the example key in the "is unset"
# message - is dropped, because it names a key that skill actually reads and is
# deliberately not shared. `|| true` keeps an absent block an empty string
# rather than a set -e abort, so the first test below reports it by name.
halt_block() {
  awk '/^The halt check below/,/^`<none>` is never a halt/' "$1" \
    | grep -v 'is unset in' || true
}

@test "every halting skill carries the halt-check block" {
  local skill file
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    [ -f "$file" ]
    if [ -z "$(halt_block "$file")" ]; then
      echo "$skill has no halt-check block - it is absent, or its first or last line was reworded away from the anchors halt_block matches on" >&2
      return 1
    fi
  done
}

# The whole point: five copies, one wording.
@test "every copy of the halt-check block is identical" {
  local first skill file block
  first="$(halt_block "$DOTFILES_ROOT/agents/skills/${HALTING_SKILLS[0]}/SKILL.md")"
  [ -n "$first" ]
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    block="$(halt_block "$file")"
    if [ "$block" != "$first" ]; then
      echo "$skill's halt-check block has drifted from ${HALTING_SKILLS[0]}'s" >&2
      diff <(printf '%s\n' "$first") <(printf '%s\n' "$block") >&2 || true
      return 1
    fi
  done
}

# The sync note is what tells an editor the copies are shared and where the
# enforcement lives. A copy that loses it invites the drift this file exists to
# stop, and a renamed test file leaves five stale pointers behind.
@test "the block names this test as what pins it" {
  local skill block
  for skill in "${HALTING_SKILLS[@]}"; do
    block="$(halt_block "$DOTFILES_ROOT/agents/skills/$skill/SKILL.md")"
    if ! printf '%s\n' "$block" | grep -F 'tests/wf-config-halt-check.bats' >/dev/null; then
      echo "$skill's halt-check block does not name tests/wf-config-halt-check.bats" >&2
      return 1
    fi
  done
}

# The halt message is the one line that legitimately differs, so it has to
# still be there in every copy - dropping it is how the diff above would go
# quiet on a real divergence.
@test "every skill still carries an unset halt message naming a key" {
  local skill file
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    if ! grep -E '^> `[a-z.-]+` is unset in `\.wf\.yml`\.' "$file" >/dev/null; then
      echo "$skill has no '<key> is unset in .wf.yml' halt message" >&2
      return 1
    fi
  done
}
