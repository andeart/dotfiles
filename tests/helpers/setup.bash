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
