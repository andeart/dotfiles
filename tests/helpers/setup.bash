#!/usr/bin/env bash
# Shared setup for dotfiles bats tests. Sourced by each .bats file.

DOTFILES_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
DOTFILES_BIN="$DOTFILES_ROOT/bin/dotfiles"
DOTFILES_TEST_BIN="$DOTFILES_ROOT/bin/dotfiles_test"

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
