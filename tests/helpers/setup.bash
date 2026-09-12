#!/usr/bin/env bash
# Shared setup for dotfiles bats tests. Sourced by each .bats file.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTFILES_BIN="$DOTFILES_ROOT/bin/dotfiles"
DOTFILES_TEST_BIN="$DOTFILES_ROOT/bin/dotfiles_test"

# Clear git's repo-local env vars. Under the pre-commit hook, git exports
# GIT_INDEX_FILE=.git/index (and friends) pointing at the dotfiles repo. Left
# in place, they leak into any temp repo a test builds and break git operations
# like `git worktree add`. Harmless when the suite is run standalone. bats
# re-sources this file for every test, so the scrub runs before each one.
scrub_git_env() {
  unset $(git rev-parse --local-env-vars)
}
scrub_git_env

# fail <message>: print a diagnosable failure message to stderr, then fail.
# Neither bats-core nor any helper loaded here defines `fail` - without this,
# the `[ cond ] || fail "..."` idiom used across several test files fails on
# an undefined command instead of printing why.
fail() {
  printf '%s\n' "$1" >&2
  return 1
}

# assert_sole_call <skill-file> <call-line>: the script <call-line> runs is
# named on exactly one line of <skill-file>, that line is <call-line> whole, and
# it sits alone between an opening bash fence and a closing one. A skill that
# stops calling the script leaves its suite grading code the skill never runs,
# and a line after the call reports its own exit status over a script that
# stopped short.
assert_sole_call() {
  local file=$1 call=$2 script count context
  script=${call#"bash ~/.agents/skills/"}
  script=${script%% *}
  count="$(grep -c -F -e "$script" "$file" || true)"
  [ "$count" = 1 ] || fail "expected $script named on one line of $file, found $count"
  context="$(grep -B1 -A1 -F -e "$script" "$file")"
  [ "$context" = "$(printf '```bash\n%s\n```' "$call")" ] \
    || fail "$(printf 'the call to %s is not alone in its block:\n%s' "$script" "$context")"
}

# script_shells: /bin/bash and whichever bash is first on PATH, resolved and
# deduplicated, skipping any this machine lacks. A skill calls a script as
# `bash <path>`, which takes PATH's bash; on macOS /bin/bash is still 3.2, the
# leg that call never reaches. On the ubuntu-latest runner both are one binary.
script_shells() {
  local sh path seen=" "
  for sh in /bin/bash bash; do
    path="$(command -v "$sh" 2>/dev/null)" || continue
    [ -n "$path" ] || continue
    case "$seen" in *" $path "*) continue ;; esac
    seen="$seen$path "
    printf '%s\n' "$path"
  done
}

# assert_script_portable <before> <script> [<arg>...]: runs <script> under every
# shell script_shells names, calling the function <before> ahead of each run
# (`:` for none), and fails when a run exits non-zero or prints other than the
# first shell did. Leaves the first shell's stdout in $output for the caller's
# content assertions: without those, a script that prints nothing passes,
# identically, under every shell.
assert_script_portable() {
  local before=$1 script=$2 sh out st first= ran=0
  shift 2
  while IFS= read -r sh; do
    # The caller's fixture reset, or the second shell grades the first one's
    # side effects.
    "$before"
    st=0
    out="$("$sh" "$script" "$@" 2>/dev/null)" || st=$?
    [ "$st" -eq 0 ] || fail "$sh exited $st running $script"
    if [ "$ran" -eq 0 ]; then
      first="$out"
    else
      [ "$out" = "$first" ] \
        || fail "$(printf '%s disagreed with the first shell:\n--- first ---\n%s\n--- %s ---\n%s' "$sh" "$first" "$sh" "$out")"
    fi
    ran=$((ran + 1))
  done < <(script_shells)

  [ "$ran" -ge 1 ] || fail "no shell available to run $script"

  # How many shells run is a property of the host, not of the script: the CI
  # image ships one bash, so the loop runs once there. What is not allowed is a
  # host that *has* a named shell and silently skips it - a dedup bug in
  # script_shells is exactly how that happens with nothing turning red.
  local want wantpath covered listed skipped=
  for want in /bin/bash bash; do
    wantpath="$(command -v "$want" 2>/dev/null)" || continue
    covered=no
    # Whole-line comparison, not a substring one: /opt/homebrew/bin/bash ends
    # in /bin/bash, so a `case` glob would count the homebrew build as coverage
    # of the 3.2 one macOS ships - hiding the exact leg this is here to find.
    while IFS= read -r listed; do
      [ "$listed" = "$wantpath" ] && covered=yes
    done < <(script_shells)
    [ "$covered" = yes ] || skipped="$skipped $want"
  done
  [ -z "$skipped" ] || fail "shells installed here but never run:$skipped"

  output="$first"
}

# Point git at a fixed config instead of the caller's. scrub_git_env cannot do
# this: --local-env-vars covers GIT_CONFIG and GIT_CONFIG_COUNT but not
# GIT_CONFIG_GLOBAL/GIT_CONFIG_SYSTEM, so ~/.gitconfig still applied. An
# inherited commit.gpgsign=true then breaks every test commit on a machine
# without the signing key. Pinning identity and defaultBranch too keeps repos
# built by a bare `git init` off git's machine-derived fallbacks.
TEST_GITCONFIG="${BATS_RUN_TMPDIR:-${TMPDIR:-/tmp}}/dotfiles-test-gitconfig"
cat > "$TEST_GITCONFIG" <<'EOF'
[user]
	name = Test
	email = test@example.com
[commit]
	gpgsign = false
[tag]
	gpgsign = false
[init]
	defaultBranch = main
EOF
export GIT_CONFIG_GLOBAL="$TEST_GITCONFIG"
export GIT_CONFIG_SYSTEM=/dev/null

# Detach stdin from the caller's terminal. bats does not redirect stdin, so a
# suite run from an interactive shell inherits its tty. Any code under test that
# gates on `[ -t 0 ]` - `_offer_merge_conflicts` does - then takes its interactive
# branch and blocks forever on `read`, with the prompt hidden inside `run`'s
# captured output. Tests that drive a prompt feed it explicitly (`<<< "y"`),
# which overrides this redirect, so they are unaffected.
exec < /dev/null

# Make a fresh tmp area for each test. Sets:
#   $TEST_REPO  — fake repo root with agents/ and claude/ subtrees
#   $TEST_LIVE  — fake $HOME containing .agents/ and .claude/
#   $TEST_STATE — fake ~/.dotfiles/sync-state.json path
make_tmp_world() {
  local tmp
  tmp="$(mktemp -d)"
  TEST_REPO="$tmp/repo"
  TEST_LIVE="$tmp/home"
  TEST_STATE="$tmp/home/.dotfiles/sync-state.json"
  mkdir -p "$TEST_REPO/agents/skills/example-skill" \
           "$TEST_REPO/claude" \
           "$TEST_LIVE/.agents" \
           "$TEST_LIVE/.claude" \
           "$TEST_LIVE/.dotfiles"
  echo "@~/.agents/AGENTS.md" > "$TEST_REPO/agents/AGENTS.md"
  echo "skill body" > "$TEST_REPO/agents/skills/example-skill/SKILL.md"
  echo "@~/.agents/AGENTS.md" > "$TEST_REPO/claude/CLAUDE.md"
  echo "{}" > "$TEST_REPO/claude/settings.json"
  echo "#!/usr/bin/env bash" > "$TEST_REPO/claude/statusline-command.sh"
}

# make_tmp_world plus the vscode/ and brew/ files the freeze helpers read. Both
# carry a marker value no real machine would produce, so a test that reads the
# wrong root shows it in the assertion rather than passing by coincidence.
make_freeze_world() {
  make_tmp_world
  mkdir -p "$TEST_REPO/vscode" "$TEST_REPO/brew"
  echo "publisher.temp-root-only" > "$TEST_REPO/vscode/extensions.txt"
  cat > "$TEST_REPO/brew/Brewfile" <<'EOF'
brew "temp-root-only-formula"
cask "temp-root-only-cask"
EOF
}
