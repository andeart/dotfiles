#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

# The halt - stop when the repo's .wf.yml never declared a key the skill needs -
# is one contract applied by five skills. It used to be thirteen lines of prose
# in each of them, pinned against each other here because nothing else could:
# a wording change in one was invisible until a skill halted differently from
# its neighbours.
#
# It is now the resolver's `--require`, so the wording lives in one place and
# this file's job changed with it. What is left to pin is the wiring: that each
# skill still passes a list, that the list is spelled in keys the resolver
# accepts, and that the one paragraph still explaining the halt has not drifted
# between copies.
#
# It is deliberately not the same test as tests/wf-config-keys.bats: that one
# pins each skill's --require list against its prose and against KNOWN_SHAPES.
# This pins the mechanism that consumes the list.

HALTING_SKILLS=(wf-ship wf-status wf-shape wf-spec-review wf-impl-review)

# The four that emit wfconfig_path=. /wf-status and /wf-shape are not here:
# neither runs verify.commands and neither writes the file, so neither has a
# source to disclose.
PATH_SKILLS=(wf-ship wf-spec-review wf-impl-review wf-config)

# require_line <file>: the --require argument from the skill's resolver call.
# Anchored at the start of a continuation line so the prose that mentions
# `--require` in backticks cannot match.
require_line() {
  sed -n 's/^[[:space:]]*--require \([a-z0-9.,_-]*\).*$/\1/p' "$1"
}

# halt_para <file>: the one paragraph that still explains the halt. Its first
# words are the extraction anchor, so rewording them empties the block here
# even though the prose is still present - the first test below says so when it
# fires.
halt_para() {
  grep -n '^Step 0 passes that list to the resolver as `--require`' "$1" \
    | cut -d: -f2- || true
}

# step0_block <file>: the lines of the skill's first ```bash fence, which is
# its Step 0 block in all four files.
step0_block() {
  awk '
    /^```bash$/ { if (done) exit; inblock = 1; next }
    inblock && /^```$/ { done = 1; inblock = 0; next }
    inblock
  ' "$1"
}

# wfconfig_block <file>: the three-line wfconfig_path= block inside the
# skill's Step 0 block - from the line naming it to the line closing the
# command substitution it opens. Empty if the block is missing or its shape
# has drifted away from what this matches on.
wfconfig_block() {
  step0_block "$1" | awk '
    /wfconfig_path=/ { grab = 1 }
    grab { print }
    grab && /print-config-path.*\)"/ { exit }
  '
}

@test "every halting skill passes a --require list to the resolver" {
  local skill file keys
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    [ -f "$file" ]
    keys="$(require_line "$file")"
    if [ -z "$keys" ]; then
      echo "$skill's resolver call carries no --require list, so it halts on nothing" >&2
      return 1
    fi
  done
}

# The strongest check available: hand each skill's list to the real script.
# A typo fails nowhere in prose - `states.in_review` matches no dump line, so
# the skill would report it unset forever and /wf-config could never fill it,
# because it is not a key. The resolver rejects it as a usage error instead.
@test "every key a skill requires is one the resolver accepts" {
  local skill file keys
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    keys="$(require_line "$file")"
    run bash "$RESOLVE" --repo-root "$DOTFILES_ROOT" --require "$keys"
    if [ "$status" -ne 0 ]; then
      echo "$skill requires '$keys', which this repo's own complete .wf.yml does not satisfy:" >&2
      echo "$output" >&2
      return 1
    fi
  done
}

# This repo declares all nine keys, so the test above can only fail on a typo -
# never on a key that is merely unset. Guard that premise rather than assume it.
@test "this repo's own config satisfies every key in KNOWN_SHAPES" {
  local shapes keys
  shapes="$(bash -c '_WF_LIB_ONLY=1 source "$0"; printf "%s\n" "${KNOWN_SHAPES[@]}"' "$RESOLVE")"
  [ -n "$shapes" ]
  keys="$(printf '%s\n' "$shapes" | sed 's/\.N$//' | paste -sd, -)"
  run bash "$RESOLVE" --repo-root "$DOTFILES_ROOT" --require "$keys"
  [ "$status" -eq 0 ]
}

# One paragraph, five copies. Fewer than the thirteen lines it replaced, but
# still duplicated, so still worth pinning against itself.
@test "every copy of the halt paragraph is identical" {
  local first skill file para
  first="$(halt_para "$DOTFILES_ROOT/agents/skills/${HALTING_SKILLS[0]}/SKILL.md")"
  [ -n "$first" ]
  for skill in "${HALTING_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    para="$(halt_para "$file")"
    if [ -z "$para" ]; then
      echo "$skill has no halt paragraph - it is absent, or its opening was reworded away from the anchor halt_para matches on" >&2
      return 1
    fi
    if [ "$para" != "$first" ]; then
      echo "$skill's halt paragraph has drifted from ${HALTING_SKILLS[0]}'s" >&2
      diff <(printf '%s\n' "$first") <(printf '%s\n' "$para") >&2 || true
      return 1
    fi
  done
}

# The paragraph is what tells an editor the copies are shared and where the
# enforcement lives. A renamed test file otherwise leaves five stale pointers.
@test "the halt paragraph names this test as what pins it" {
  local skill para
  for skill in "${HALTING_SKILLS[@]}"; do
    para="$(halt_para "$DOTFILES_ROOT/agents/skills/$skill/SKILL.md")"
    if ! printf '%s\n' "$para" | grep -F 'tests/wf-config-halt-check.bats' >/dev/null; then
      echo "$skill's halt paragraph does not name tests/wf-config-halt-check.bats" >&2
      return 1
    fi
  done
}

# /wf-wrap is the documented exception: it reads a key but must never halt,
# because by the step that reads it the worktree is gone and the branch deleted.
# --require is opt-in precisely so that stays expressible.
@test "wf-wrap requires nothing, so it cannot halt after its cleanup has run" {
  local file
  file="$DOTFILES_ROOT/agents/skills/wf-wrap/SKILL.md"
  [ -f "$file" ]
  if [ -n "$(require_line "$file")" ]; then
    echo "wf-wrap passes --require, which would let it fail after the worktree is gone" >&2
    return 1
  fi
}

# The single property the placement rule rests on, and the one that was wrong
# when the rule was first written: /wf-ship reads everything under its
# `status<<<` marker as porcelain, where no output means a clean tree, so a
# wfconfig_path= line under it sends a clean tree to be staged and committed.
# Nothing else in the suite would notice the line drifting back under a marker.
@test "each skill's wfconfig_path line sits above every marker its Step 0 block opens" {
  local skill file block path_at marker_at
  for skill in "${PATH_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    [ -f "$file" ]
    block="$(step0_block "$file")"
    path_at="$(printf '%s\n' "$block" | grep -n 'wfconfig_path=' | sed -n '1s/:.*//p')"
    marker_at="$(printf '%s\n' "$block" | grep -n "<<<'" | sed -n '1s/:.*//p')"
    if [ -z "$path_at" ]; then
      echo "$skill's Step 0 block emits no wfconfig_path= line" >&2
      return 1
    fi
    if [ -z "$marker_at" ]; then
      echo "$skill's Step 0 block opens no <<< marker, so this test grades nothing" >&2
      return 1
    fi
    if [ "$path_at" -ge "$marker_at" ]; then
      echo "$skill emits wfconfig_path= at block line $path_at, under the marker at $marker_at" >&2
      return 1
    fi
  done
}

# The block is deliberately copy-pasted four times - SKILL.md has no include
# mechanism - so nothing but a test keeps the copies from drifting apart. The
# case above pins each copy's position relative to its marker but not its
# content, so someone could edit one copy (drop `--repo-root "$root"`, say,
# which makes the resolver default to `.` and resolve whatever directory the
# agent happens to be standing in) and every other case here would still pass.
#
# Scope: the bash fence only. Each skill's prose about `wfconfig_path=` differs
# legitimately - only two of the four have a Step 3 gate to point at - so it is
# not gradable here, and it has drifted before.
@test "every copy of the wfconfig_path block is identical" {
  local first skill file block
  first="$(wfconfig_block "$DOTFILES_ROOT/agents/skills/${PATH_SKILLS[0]}/SKILL.md")"
  [ -n "$first" ]
  for skill in "${PATH_SKILLS[@]}"; do
    file="$DOTFILES_ROOT/agents/skills/$skill/SKILL.md"
    block="$(wfconfig_block "$file")"
    if [ -z "$block" ]; then
      echo "$skill has no wfconfig_path= block, or its shape has drifted from what wfconfig_block matches on" >&2
      return 1
    fi
    if [ "$block" != "$first" ]; then
      echo "$skill's wfconfig_path= block has drifted from ${PATH_SKILLS[0]}'s" >&2
      diff <(printf '%s\n' "$first") <(printf '%s\n' "$block") >&2 || true
      return 1
    fi
  done
}
