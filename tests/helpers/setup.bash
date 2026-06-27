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
