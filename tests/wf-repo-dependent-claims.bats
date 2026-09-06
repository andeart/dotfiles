#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# The skills under agents/skills/ are deployed to ~/.claude/skills and
# ~/.agents/skills, so every repo on the machine runs the same copy and "this
# repo" inside one of them resolves to whichever repo the agent is standing in.
# The sharpest form of the defect is a skill that tells the agent to run a
# check and then tells it the answer: an agent handed the answer has little
# reason to run the check, so the mechanism underneath goes unused and the
# wrong branch gets taken.
#
# AGENTS.md carries the rule, which reaches phrasings a grep never will. This
# file is its complement, not its replacement: it catches the phrasings the
# rule has already been broken with. The two are asserted together below,
# because without that the rule can be deleted while this list stays green.
#
# The glob is every skill rather than wf-*. The rule is written about a skill,
# and a test narrower than the rule it enforces drifts from it.

# Literals, matched with grep -F. An entry earns its place by having been seen
# in a real skill - this is not a list of phrasings someone might one day
# write.
BANNED=(
  'gitignored here'
  'so it is always `no` here'
)

# The clause the AGENTS.md rule cannot lose and still be the same rule. Reword
# freely around it.
RULE_ANCHOR='it must never say "the answer is Y"'

# A paragraph in wf-ship that is phrased the way the rule asks - it names the
# repo property as a condition and says outright that it is not a special case
# here. It has to stay clear of the literal list, or the list is over-broad and
# a correct skill cannot be written.
WELL_PHRASED='A repo that gitignores all of `docs/` can never produce a docs-only push'

skill_files() {
  printf '%s\n' "$DOTFILES_ROOT"/agents/skills/*/SKILL.md
}

@test "the banned-phrase list is not empty" {
  # An emptied list would make the sweep below pass over anything at all.
  [ "${#BANNED[@]}" -gt 0 ]
}

@test "the skills glob names real files" {
  # An unmatched glob expands to itself, and grep over a path that does not
  # exist reports nothing found - which reads exactly like a clean sweep.
  local f count=0
  while IFS= read -r f; do
    [ -f "$f" ] || fail "the skills glob produced a non-file: $f"
    count=$((count + 1))
  done < <(skill_files)
  [ "$count" -gt 1 ] || fail "the skills glob matched $count files"
}

@test "no skill states the answer to a check the repo decides" {
  local phrase f hits
  for phrase in "${BANNED[@]}"; do
    while IFS= read -r f; do
      hits="$(grep -n -F -e "$phrase" "$f" || true)"
      [ -z "$hits" ] || fail "$(printf '%s carries "%s":\n%s\n\nA skill may say "if the repo does X, the answer is Y". It may not say "the answer is Y" - state the rule and let the check answer. See the rule in AGENTS.md.' "${f#"$DOTFILES_ROOT"/}" "$phrase" "$hits")"
    done < <(skill_files)
  done
}

@test "AGENTS.md still carries the written rule" {
  # Decision 5's two halves are complements. Without this, the rule can be
  # deleted while the phrase list above stays green, leaving one half of a
  # pair doing the work of both.
  grep -n -F -e "$RULE_ANCHOR" "$DOTFILES_ROOT/AGENTS.md" > /dev/null \
    || fail "AGENTS.md no longer carries the repo-dependent-claims rule"
}

@test "a correctly phrased repo-dependent paragraph does not trip the list" {
  local line phrase
  line="$(grep -F -e "$WELL_PHRASED" "$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md")"
  [ -n "$line" ] || fail "wf-ship no longer carries the docs-only-push paragraph this case is about"
  for phrase in "${BANNED[@]}"; do
    printf '%s\n' "$line" | grep -F -e "$phrase" > /dev/null \
      && fail "the banned-phrase list flags a correctly phrased paragraph: $phrase"
  done
  # `grep` inside the loop above exits 1 on the pass, which is the outcome
  # this case wants; land on a zero status so the test does not turn on it.
  true
}
