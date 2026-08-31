#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

IMPL="$DOTFILES_ROOT/agents/skills/wf-impl-review/SKILL.md"
SPEC="$DOTFILES_ROOT/agents/skills/wf-spec-review/SKILL.md"

# wf-impl-review/SKILL.md and wf-spec-review/SKILL.md both say the check-state
# block - establish it, carry it as <CHECK_STATE>, re-establish it after a
# commit, the no-bullet-items gate - is identical between them "by design" and
# ask an editor to "keep the two in sync." Nothing enforced that until now:
# this extracts both copies straight out of the markdown and pins them against
# each other, the same way tests/wf-wrap-gh-jq.bats pins a jq program against
# the SKILL.md it still lives in, so a wording change to one that forgets the
# other fails here instead of surfacing in a review three months later.

# check_state_block <file>: the check-state paragraphs through the
# no-bullet-items gate, in two ranges - the fenced opening-prompt template
# between them is never claimed identical (it names a worktree path or a spec
# path outright) and is deliberately excluded.
check_state_block() {
  {
    sed -n '/^The check-state paragraphs below/,/^The numbered focus list carries/p' "$1"
    sed -n '/^\*\*When that sub-agent finishes\*\*/,/^\*\*No bullet items at all\*\*/p' "$1"
  }
}

@test "both files still carry the check-state block where this test expects it" {
  local impl_lines spec_lines
  impl_lines="$(check_state_block "$IMPL" | wc -l | tr -d ' ')"
  spec_lines="$(check_state_block "$SPEC" | wc -l | tr -d ' ')"
  # A heading reword that breaks the sed anchors would silently extract
  # nothing (or a truncated range) rather than error - catch that here so the
  # sync test below fails loudly with a reason, not by quietly comparing two
  # empty strings.
  [ "$impl_lines" -gt 20 ]
  [ "$spec_lines" -gt 20 ]
  [ "$impl_lines" = "$spec_lines" ]
}

@test "the check-state block agrees between wf-impl-review and wf-spec-review outside the three documented per-skill lines" {
  local impl spec impl_trimmed spec_trimmed
  impl="$(check_state_block "$IMPL")"
  spec="$(check_state_block "$SPEC")"
  # Line 1 names the sibling file the paragraph below is identical to (so it
  # has to differ - each file names the other one). Line 15 is
  # "Re-establish it after any round that committed.", where wf-spec-review
  # alone explains the <SPEC_TRACKED> case. Line 19 is "Spawn a sub-agent",
  # where the substitution list names a worktree path plus a resolved default
  # branch for wf-impl-review, and only a spec path for wf-spec-review. All
  # three are read separately in the two tests below; every other line has to
  # match exactly, or the two copies have drifted apart.
  impl_trimmed="$(printf '%s\n' "$impl" | sed '1d;15d;19d')"
  spec_trimmed="$(printf '%s\n' "$spec" | sed '1d;15d;19d')"
  [ "$impl_trimmed" = "$spec_trimmed" ]
}

@test "the check-state block's line 1 names its own sibling file" {
  [[ "$(check_state_block "$IMPL" | sed -n '1p')" == *'`wf-spec-review/SKILL.md`'* ]]
  [[ "$(check_state_block "$SPEC" | sed -n '1p')" == *'`wf-impl-review/SKILL.md`'* ]]
}

@test "only wf-spec-review's re-establish paragraph carries the SPEC_TRACKED case" {
  [[ "$(check_state_block "$IMPL" | sed -n '15p')" != *SPEC_TRACKED* ]]
  [[ "$(check_state_block "$SPEC" | sed -n '15p')" == *SPEC_TRACKED* ]]
}

@test "only wf-impl-review's spawn paragraph substitutes a worktree path and a resolved default branch" {
  [[ "$(check_state_block "$IMPL" | sed -n '19p')" == *"the worktree path"* ]]
  [[ "$(check_state_block "$IMPL" | sed -n '19p')" == *"the resolved default branch"* ]]
  [[ "$(check_state_block "$SPEC" | sed -n '19p')" == *"the spec path"* ]]
  [[ "$(check_state_block "$SPEC" | sed -n '19p')" != *"the resolved default branch"* ]]
}
