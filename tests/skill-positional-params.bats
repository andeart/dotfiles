#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# The harness replaces each `$` followed by a digit, and each `$ARGUMENTS`, in a
# SKILL.md with the invocation arguments, in prose and in code. The changed text
# usually still runs, so a broken check reports "found nothing" instead of an
# error, and only for some argument strings. The harness can change only a form
# that is in the file, so a scan of the files is the full guarantee.
#
# AGENTS.md states the rule, and this file enforces it. The last case checks the
# rule text, so the rule cannot be deleted while the scan stays green.
#
# The pattern is wider than the harness's `\$(\d+)(?!\w)`. It has no lookahead,
# so it does not depend on the harness version. It also flags `\$1`: the harness
# does not replace that form, but it is a syntax error in awk. It covers only the
# argument forms, because the `${CLAUDE_*}` values do not change with the
# arguments.
PATTERN='\$([0-9]|ARGUMENTS)'

# Forms that the pattern must flag. Without this list, a pattern edited to match
# nothing passes the scan for any file.
UNSAFE=( '$0' '$1' '$10' '$ARGUMENTS' '$ARGUMENTS[0]' '\$1' )

# Safe forms taken from the skills. A case checks that a skill still holds each
# one, because a control that no skill holds tests nothing.
REAL_SAFE=( '$(git rev-parse' '$?' '$root' )

# Safe forms that no skill holds, so there is no presence check. The harness does
# not replace `$(1)` or `${1}`, because a digit must follow the `$` directly.
# `([^0-9]|$)` catches a matcher that flags `$)`.
SYNTHETIC_SAFE=( '$(1)' '${1}' '([^0-9]|$)' )

# The ban, and the reason that each rewording of the rule must keep.
RULE_ANCHORS=(
  'neither may appear anywhere in a SKILL.md'
  'fails toward "found nothing" rather than toward an error'
)

# frontmatter_arguments <file>...: each top-level `arguments:` key between the
# opening `---` of a file and the next `---`, as `file:line: text`. It matches
# the exact key, so `argument-hint:` passes, and only in frontmatter, so prose
# about the rule passes.
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
