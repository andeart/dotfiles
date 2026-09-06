#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

IMPL="$DOTFILES_ROOT/agents/skills/wf-impl-review/SKILL.md"
SPEC="$DOTFILES_ROOT/agents/skills/wf-spec-review/SKILL.md"

# wf-impl-review/SKILL.md and wf-spec-review/SKILL.md both say the check-state
# block - establish it, carry it as <CHECK_STATE>, re-establish it after a
# commit, the no-bullet-items gate - is identical between them "by design" and
# ask an editor to "keep the two in sync." This enforces that: it extracts both
# copies straight out of the markdown and pins them against each other, the way
# tests/wf-wrap-gh-jq.bats pins a jq program against the SKILL.md it lives in,
# so a wording change to one that forgets the other fails here rather than
# surfacing in a review months later.

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

# The three paragraphs below are read out of the block by the text each one
# starts with, not by position - a paragraph landing above or below them in a
# future edit changes their line number without changing their content, and
# pinning by position would then need recomputing for a change that has
# nothing to do with what these three tests actually check. sibling_line(),
# reestablish_line() and spawn_line() each grep for a prefix that appears
# exactly once in the block; a rewording that drops the prefix itself is
# exactly the drift this file exists to catch, and shows up as that grep
# coming back empty rather than as a silently wrong line.
sibling_line() { check_state_block "$1" | grep -F 'The check-state paragraphs below'; }
reestablish_line() { check_state_block "$1" | grep -F '**Re-establish it after any round that committed.**'; }
spawn_line() { check_state_block "$1" | grep -F '**Spawn a sub-agent**'; }

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
  # The sibling-file line names the sibling file the paragraph is identical
  # to (so it has to differ - each file names the other one). The
  # re-establish paragraph is where wf-spec-review alone explains the
  # <SPEC_TRACKED> case. The spawn paragraph's substitution list names a
  # worktree path plus a resolved default branch for wf-impl-review, and only
  # a spec path for wf-spec-review. All three are read separately in the two
  # tests below; every other line has to match exactly, or the two copies
  # have drifted apart.
  impl_trimmed="$(printf '%s\n' "$impl" | grep -v -F \
    -e 'The check-state paragraphs below' \
    -e '**Re-establish it after any round that committed.**' \
    -e '**Spawn a sub-agent**')"
  spec_trimmed="$(printf '%s\n' "$spec" | grep -v -F \
    -e 'The check-state paragraphs below' \
    -e '**Re-establish it after any round that committed.**' \
    -e '**Spawn a sub-agent**')"
  [ "$impl_trimmed" = "$spec_trimmed" ]
}

@test "the check-state block's sibling-file line names its own sibling file" {
  [[ "$(sibling_line "$IMPL")" == *'`wf-spec-review/SKILL.md`'* ]]
  [[ "$(sibling_line "$SPEC")" == *'`wf-impl-review/SKILL.md`'* ]]
}

@test "only wf-spec-review's re-establish paragraph carries the SPEC_TRACKED case" {
  [[ "$(reestablish_line "$IMPL")" != *SPEC_TRACKED* ]]
  [[ "$(reestablish_line "$SPEC")" == *SPEC_TRACKED* ]]
}

@test "only wf-impl-review's spawn paragraph substitutes a worktree path and a resolved default branch" {
  [[ "$(spawn_line "$IMPL")" == *"the worktree path"* ]]
  [[ "$(spawn_line "$IMPL")" == *"the resolved default branch"* ]]
  [[ "$(spawn_line "$SPEC")" == *"the spec path"* ]]
  [[ "$(spawn_line "$SPEC")" != *"the resolved default branch"* ]]
}
