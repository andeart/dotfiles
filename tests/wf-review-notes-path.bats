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

# step_two <file>: the Step 2 section, where the coordinator resolves the
# directory the opening prompt's <ABSOLUTE NOTES PATH> is built from.
step_two() {
  sed -n '/^## Step 2:/,/^## Step 3:/p' "$1"
}

# The placeholder above is only half the mechanism. Nothing downstream re-reads
# the path, so a coordinator left to improvise one puts the notes back inside
# the working tree and the leak returns with the docs/reviews guard above still
# green. These pin the resolution itself, not just its absence.

@test "both review skills resolve the notes directory in Step 2" {
  local f block
  for f in "$IMPL" "$SPEC"; do
    block="$(step_two "$f")"
    [ -n "$block" ] || fail "Step 2 of $f did not extract - has the heading moved?"
    [[ "$block" == *"notes directory"* ]] \
      || fail "Step 2 of $f names no notes directory to resolve"
    [[ "$block" == *"scratchpad"* ]] \
      || fail "Step 2 of $f does not say where the notes directory comes from"
    [[ "$block" == *"mktemp -d"* ]] \
      || fail "Step 2 of $f offers no fallback for a session with no scratchpad"
    [[ "$block" == *"absolute"* ]] \
      || fail "Step 2 of $f does not require the notes path be absolute"
    [[ "$block" == *'$root'* ]] \
      || fail "Step 2 of $f does not hold the notes path outside Step 0's \$root"
  done
}

@test "the notes directory is resolved before the prompt that substitutes it" {
  local f resolved used
  for f in "$IMPL" "$SPEC"; do
    resolved="$(grep -n -F '**The notes directory**' "$f" | cut -d: -f1)"
    used="$(grep -n -F '<ABSOLUTE NOTES PATH>' "$f" | cut -d: -f1)"
    [ -n "$resolved" ] || fail "$f never resolves a notes directory"
    [ "$resolved" -lt "$used" ] \
      || fail "$f substitutes the notes path at line $used before resolving it at line $resolved"
  done
}

@test "wf-ship's cleanup path list no longer names docs/reviews" {
  run grep -n -F 'docs/reviews' "$SHIP"
  [ "$status" -ne 0 ] || fail "docs/reviews is back in $SHIP:
$output"
}
