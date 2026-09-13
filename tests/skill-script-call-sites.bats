#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

# A skill calls a script as `bash ~/.agents/skills/<skill>/scripts/<name>.sh`.
# `bash`, so the call does not need the execute bit of the file. The fixed path,
# because a skill runs in every repo, where a repo-relative path fails, and
# because most calls run the script of a different skill. One call in another
# form gives the next copy a wrong example, so every call uses this form.
#
# The check joins continuations first, so a call on several lines reads as one.
# It reads the whole file, not only the fenced blocks. Prose names a script by
# its file name only, so a path with a directory in prose also fails.

NAMED='[a-z0-9-]+/scripts/[a-z0-9-]+\.sh'
CALLED="bash[[:space:]]+~/\\.agents/skills/$NAMED"

# misnamed_sites <file>: each joined line that still names a script after its
# fixed-form calls are removed. ENVIRON, not -v, because -v processes the
# backslashes in the regexes as escapes.
misnamed_sites() {
  join_continuations "$1" | CALLED="$CALLED" NAMED="$NAMED" FILE="$1" awk '
    { rest = $0; gsub(ENVIRON["CALLED"], "", rest) }
    rest ~ ENVIRON["NAMED"] { print ENVIRON["FILE"] ": " $0 }'
}

# called_scripts <file>: the `<skill>/scripts/<name>.sh` of every fixed-form call.
called_scripts() {
  join_continuations "$1" | grep -o -E -e "$CALLED" | sed -E 's#^bash[[:space:]]+~/\.agents/skills/##' || true
}

@test "the skills glob names real files" {
  assert_skill_glob
}

@test "every script a skill names is called as bash with the fixed path" {
  local f hits=
  while IFS= read -r f; do
    hits="$hits$(misnamed_sites "$f")"
  done < <(skill_files)
  [ -z "$hits" ] || fail "$(printf 'A SKILL.md names a script outside the form bash ~/.agents/skills/<skill>/scripts/<name>.sh:\n%s\n\nIn prose, name the script by its bare filename.' "${hits//$DOTFILES_ROOT\//}")"
}

@test "every called script exists in the repo" {
  local f s count=0
  while IFS= read -r f; do
    while IFS= read -r s; do
      [ -n "$s" ] || continue
      count=$((count + 1))
      [ -f "$DOTFILES_ROOT/agents/skills/$s" ] \
        || fail "${f#"$DOTFILES_ROOT"/} calls a script the repo does not carry: $s"
    done < <(called_scripts "$f")
  done < <(skill_files)
  # A pattern that matches no call passes the loop above for any file.
  [ "$count" -gt 0 ] || fail "no fixed-form call found in any skill"
}

@test "the check refuses every other form and accepts the fixed one" {
  local bad="$BATS_TEST_TMPDIR/bad.md" good="$BATS_TEST_TMPDIR/good.md"
  cat > "$bad" <<'EOF'
agents/skills/x/scripts/y-z.sh <branch-name>
bash ~/.claude/skills/x/scripts/y-z.sh
~/.agents/skills/x/scripts/y-z.sh
sh ~/.agents/skills/x/scripts/y-z.sh
Prose pointing at x/scripts/y-z.sh.
EOF
  cat > "$good" <<'EOF'
bash ~/.agents/skills/x/scripts/y-z.sh '<ID>'
out=$(bash \
  ~/.agents/skills/x/scripts/y-z.sh --flag)
Prose naming y-z.sh alone.
EOF

  [ "$(misnamed_sites "$bad" | wc -l | tr -d ' ')" -eq 5 ] \
    || fail "$(printf 'expected all five bad forms flagged, got:\n%s' "$(misnamed_sites "$bad")")"
  [ -z "$(misnamed_sites "$good")" ] \
    || fail "$(printf 'a fixed-form call was flagged:\n%s' "$(misnamed_sites "$good")")"
  [ "$(called_scripts "$good")" = "$(printf 'x/scripts/y-z.sh\nx/scripts/y-z.sh')" ] \
    || fail "$(printf 'the fixed-form calls did not both resolve:\n%s' "$(called_scripts "$good")")"
}
