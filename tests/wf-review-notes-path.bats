#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

IMPL="$DOTFILES_ROOT/agents/skills/wf-impl-review/SKILL.md"
SPEC="$DOTFILES_ROOT/agents/skills/wf-spec-review/SKILL.md"
SHIP="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"

# Reviewer notes moved out of the working tree so a later reviewer cannot read
# an earlier one's. Measured 2026-09-04: two of four reviewers dispatched
# sub-agents to read docs/reviews/ during their read-only phase. The path
# coming back would restore the leak silently, so it is guarded here rather
# than left to review.

@test "neither review skill mentions docs/reviews" {
  run grep -n -F 'docs/reviews' "$IMPL"
  [ "$status" -ne 0 ] || fail "docs/reviews is back in $IMPL:
$output"
  run grep -n -F 'docs/reviews' "$SPEC"
  [ "$status" -ne 0 ] || fail "docs/reviews is back in $SPEC:
$output"
}

@test "neither review skill still probes whether docs/reviews is ignored" {
  run grep -n -F 'reviews_ignored' "$IMPL"
  [ "$status" -ne 0 ] || fail "reviews_ignored probe is back in $IMPL"
  run grep -n -F 'reviews_ignored' "$SPEC"
  [ "$status" -ne 0 ] || fail "reviews_ignored probe is back in $SPEC"
}

@test "both opening prompts name an absolute notes path placeholder" {
  run grep -c -F '<ABSOLUTE NOTES PATH>' "$IMPL"
  [ "$output" = "1" ]
  run grep -c -F '<ABSOLUTE NOTES PATH>' "$SPEC"
  [ "$output" = "1" ]
}

@test "wf-ship's cleanup path list no longer names docs/reviews" {
  run grep -n -F 'docs/reviews' "$SHIP"
  [ "$status" -ne 0 ] || fail "docs/reviews is back in $SHIP:
$output"
}
