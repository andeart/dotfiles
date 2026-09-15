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

# skill_files: every SKILL.md under agents/skills/, one path per line.
skill_files() {
  printf '%s\n' "$DOTFILES_ROOT"/agents/skills/*/SKILL.md
}

# assert_skill_glob: skill_files names more than one real file. An unmatched
# glob expands to itself, and grep on a missing path reports no match, which
# looks the same as a clean scan.
assert_skill_glob() {
  local f count=0
  while IFS= read -r f; do
    [ -f "$f" ] || fail "the skills glob produced a non-file: $f"
    count=$((count + 1))
  done < <(skill_files)
  [ "$count" -gt 1 ] || fail "the skills glob matched $count files"
}

# join_continuations [<file>]: <file>, or stdin, with each backslash-newline
# removed, so a command on several lines reads as one line.
join_continuations() { sed -e :a -e '/\\$/N; s/\\\n//; ta' "$@"; }

# assert_one_line <file> <text>: exactly one line of <file> holds the fixed
# string <text>.
assert_one_line() {
  local count
  count="$(grep -c -F -e "$2" "$1" || true)"
  [ "$count" = 1 ] || fail "expected one line of $1 holding $2, found $count"
}

# assert_sole_call <skill-file> <call-line>: exactly one line of <skill-file>
# names the script that <call-line> runs, that line is <call-line>, and bash
# fences are directly above and below it. The first check stops a suite from
# testing a script that the skill no longer calls. The fence check stops a line
# after the call from hiding the exit status of the script.
assert_sole_call() {
  local file=$1 call=$2 script context
  script=${call#"bash ~/.agents/skills/"}
  script=${script%% *}
  assert_one_line "$file" "$script"
  context="$(grep -B1 -A1 -F -e "$script" "$file")"
  [ "$context" = "$(printf '```bash\n%s\n```' "$call")" ] \
    || fail "$(printf 'the call to %s is not alone in its block:\n%s' "$script" "$context")"
}

# The shells for a skill's `bash <path>` call: PATH's bash, which the call
# uses, and /bin/bash, which is 3.2 on macOS. On the ubuntu-latest runner, both
# names are one binary.
SCRIPT_SHELLS=(/bin/bash bash)

# shells_among <candidate>...: each candidate resolved through PATH, with
# duplicates and missing shells removed.
shells_among() {
  local sh path seen=" "
  for sh in "$@"; do
    path="$(command -v "$sh" 2>/dev/null)" || continue
    [ -n "$path" ] || continue
    case "$seen" in *" $path "*) continue ;; esac
    seen="$seen$path "
    printf '%s\n' "$path"
  done
}

# assert_shells_covered <ran> <candidate>...: each installed candidate resolves
# to a line of <ran>, the shells that a loop ran, one per line. The number of
# shells depends on the host, and the CI image has one bash and no zsh. An
# installed candidate that did not run is a dedup bug in shells_among, and this
# check makes it fail.
assert_shells_covered() {
  local ran=$1 want wantpath covered listed skipped=
  shift
  for want in "$@"; do
    wantpath="$(command -v "$want" 2>/dev/null)" || continue
    covered=no
    # Compare whole lines, not substrings: /opt/homebrew/bin/bash ends in
    # /bin/bash, so a `case` glob counts the Homebrew build as coverage of the
    # macOS 3.2 build and hides the missing run.
    while IFS= read -r listed; do
      [ "$listed" = "$wantpath" ] && covered=yes
    done <<< "$ran"
    [ "$covered" = yes ] || skipped="$skipped $want"
  done
  [ -z "$skipped" ] || fail "shells installed here but never run:$skipped"
}

# assert_script_portable <before> <script> [<arg>...]: runs <script> under each
# SCRIPT_SHELLS shell and calls the function <before> before each run (`:` for
# none). Fails when a run exits non-zero, when its output differs from the first
# shell's output, or when an installed shell did not run. Puts the first shell's
# stdout in $output. The caller must assert on that content, because a script
# that prints nothing passes under every shell.
assert_script_portable() {
  local before=$1 script=$2 sh out st first= ran=
  shift 2
  while IFS= read -r sh; do
    # Reset the caller's fixture, so the second shell does not see the changes
    # of the first run.
    "$before"
    st=0
    out="$("$sh" "$script" "$@" 2>/dev/null)" || st=$?
    [ "$st" -eq 0 ] || fail "$sh exited $st running $script"
    if [ -z "$ran" ]; then
      first="$out"
    else
      [ "$out" = "$first" ] \
        || fail "$(printf '%s disagreed with the first shell:\n--- first ---\n%s\n--- %s ---\n%s' "$sh" "$first" "$sh" "$out")"
    fi
    ran="$ran$sh"$'\n'
  done < <(shells_among "${SCRIPT_SHELLS[@]}")

  [ -n "$ran" ] || fail "no shell available to run $script"
  assert_shells_covered "$ran" "${SCRIPT_SHELLS[@]}"
  output="$first"
}

# output_values <key>: every value of a `key=value` line in $output, one per
# line.
output_values() { printf '%s\n' "$output" | sed -n "s/^$1=//p"; }

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

# These readers read $output as wf-ship reads the output of a script. A marker
# is `name<<<` alone on a line. Keys come only from the lines before the first
# marker. A test that reads keys from other lines passes a script that lets a
# path, a patch line or a hook print a key.

# key_values <key>: all values of <key> before the first marker, one on each
# line.
key_values() {
  printf '%s\n' "$output" | K="$1=" awk '
    /^[a-z_]+<<<$/ { exit }
    index($0, ENVIRON["K"]) == 1 { print substr($0, length(ENVIRON["K"]) + 1) }'
}

# section <name>: the lines of section <name>. residue<<< has residue_shown
# lines, pushed<<< has pushed_shown, pr_first_line<<< has one, and all other
# sections continue to the end. A line that is not a marker where a marker must
# be stops the read, so a wrong count shows as a missing section, not as a
# shifted section. With an empty <name>, it prints the name of each section, in
# order.
section() {
  printf '%s\n' "$output" | W="$1" awk '
    BEGIN { count["residue"] = "residue_shown"; count["pushed"] = "pushed_shown"; fixed["pr_first_line"] = 1 }
    !started && !/^[a-z_]+<<<$/ { eq = index($0, "="); if (eq) key[substr($0, 1, eq - 1)] = substr($0, eq + 1); next }
    !inside {
      if ($0 !~ /^[a-z_]+<<<$/) exit
      started = 1
      name = substr($0, 1, length($0) - 3)
      if (ENVIRON["W"] == "") print name
      left = (name in fixed) ? fixed[name] : ((name in count) ? key[count[name]] + 0 : -1)
      inside = (left != 0)
      next
    }
    {
      if (name == ENVIRON["W"]) print
      if (left > 0 && --left == 0) inside = 0
    }'
}

# section_names: the name of each section in $output, in order.
section_names() { section ''; }
