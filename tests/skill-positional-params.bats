#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# A SKILL.md reaches the model with its invocation's arguments substituted into
# every `$` followed by a digit and every `$ARGUMENTS`, in prose and code alike.
# The mangled text usually still runs, so the check it breaks answers "found
# nothing" rather than erroring, and only for some argument strings. The
# corruption can only touch a form present on disk, so scanning the files is the
# whole guarantee.
#
# AGENTS.md carries the rule; this file enforces it. Both are asserted below -
# without that, the rule can be deleted while the scan stays green.
#
# The pattern is deliberately looser than the harness's `\$(\d+)(?!\w)`. It
# drops the lookahead so it does not track harness versions, and it flags `\$1`,
# which escapes substitution but is a syntax error in the awk that wants it. It
# covers the argument forms only: the `${CLAUDE_*}` forms the loader also
# replaces do not vary with the arguments.
PATTERN='\$([0-9]|ARGUMENTS)'

# Forms the pattern must flag. Without these, a pattern edited into one that
# matches nothing passes the scan over anything at all.
UNSAFE=( '$0' '$1' '$10' '$ARGUMENTS' '$ARGUMENTS[0]' '\$1' )

# Negative controls taken from the skills, each re-checked as still present in
# one: a control that drifted out of every skill grades nothing.
REAL_SAFE=( '$(git rev-parse' '$?' '$root' )

# Negative controls no skill carries, so no presence check. `$(1)` and `${1}`
# are outside the substitution, which needs a digit straight after the `$`;
# `([^0-9]|$)` is where a careless matcher flags the `$)`.
SYNTHETIC_SAFE=( '$(1)' '${1}' '([^0-9]|$)' )

# The ban itself, and the why that has to survive rewording.
RULE_ANCHORS=(
  'neither may appear anywhere in a SKILL.md'
  'fails toward "found nothing" rather than toward an error'
)

# frontmatter_arguments <file>...: every top-level `arguments:` key between a
# file's opening `---` and the next one, as `file:line: text`. The exact key, so
# `argument-hint:` passes, and only in frontmatter, so prose about the rule
# passes too.
frontmatter_arguments() {
  awk '
    FNR == 1 { infm = ($0 == "---"); next }
    infm && $0 == "---" { infm = 0; next }
    infm && /^arguments[[:space:]]*:/ { print FILENAME ":" FNR ": " $0 }
  ' "$@"
}

@test "the skills glob names real files" {
  assert_skill_glob
}

@test "no SKILL.md carries a positional parameter or an ARGUMENTS reference" {
  local f files=() hits
  while IFS= read -r f; do
    files+=("$f")
  done < <(skill_files)

  hits="$(grep -n -E -e "$PATTERN" -- "${files[@]}" || true)"
  [ -z "$hits" ] || fail "$(printf 'A SKILL.md carries a form the harness substitutes with the invocation arguments:\n%s\n\nMove shell that needs a field reference into the skill'"'"'s scripts/*.sh. See the rule in AGENTS.md.' "${hits//$DOTFILES_ROOT\//}")"
}

@test "no SKILL.md declares arguments in its frontmatter" {
  local f files=() hits
  while IFS= read -r f; do
    files+=("$f")
  done < <(skill_files)

  hits="$(frontmatter_arguments "${files[@]}")"
  [ -z "$hits" ] || fail "$(printf 'A SKILL.md declares arguments, which puts each $<name> under substitution:\n%s' "${hits//$DOTFILES_ROOT\//}")"
}

@test "the frontmatter check reads only the frontmatter's exact key" {
  local flagged="$BATS_TEST_TMPDIR/flagged.md" passed="$BATS_TEST_TMPDIR/passed.md"
  printf -- '---\nname: x\narguments: [a]\n---\nbody\n' > "$flagged"
  printf -- '---\nname: x\nargument-hint: <a>\n---\narguments: in prose\n' > "$passed"

  [ -n "$(frontmatter_arguments "$flagged")" ] || fail "a declared arguments: key was not flagged"
  [ -z "$(frontmatter_arguments "$passed")" ] || fail "argument-hint: or body prose was flagged"
}

@test "the pattern flags every form it exists to catch" {
  local s
  for s in "${UNSAFE[@]}"; do
    printf '%s\n' "$s" | grep -E -e "$PATTERN" > /dev/null \
      || fail "the pattern does not flag: $s"
  done
}

@test "safe dollar forms do not trip the pattern" {
  local f s files=()
  while IFS= read -r f; do
    files+=("$f")
  done < <(skill_files)

  for s in "${REAL_SAFE[@]}"; do
    grep -F -e "$s" -- "${files[@]}" > /dev/null \
      || fail "the control is no longer in any skill: $s"
  done
  for s in "${REAL_SAFE[@]}" "${SYNTHETIC_SAFE[@]}"; do
    if printf '%s\n' "$s" | grep -E -e "$PATTERN" > /dev/null; then
      fail "the pattern flags a safe form: $s"
    fi
  done
}

@test "AGENTS.md still carries the positional-parameter rule" {
  local anchor
  for anchor in "${RULE_ANCHORS[@]}"; do
    grep -n -F -e "$anchor" "$DOTFILES_ROOT/AGENTS.md" > /dev/null \
      || fail "AGENTS.md no longer carries the positional-parameter rule: $anchor"
  done
}
