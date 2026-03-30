# Tool-agnostic agents/ migration - Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move portable AI assistant configuration into a tool-agnostic `agents/` directory, keeping Claude-specific files in `claude/`.

**Architecture:** New `agents/` top-level directory holds AGENTS.md, skills/, and agents/. `claude/` retains commands/, statusline-command.sh, and a minimal CLAUDE.md that imports AGENTS.md. bootstrap.sh creates `~/.agents/` symlinks and conditionally bridges `~/.claude/skills` and `~/.claude/agents` if Claude Code doesn't read from `~/.agents/` natively.

**Tech Stack:** Shell (bash), YAML (dotfiles.yml), Markdown

---

## File Map

**Create:**
- `agents/AGENTS.md` - shared instructions (content from current `claude/CLAUDE.md`)
- `agents/skills/suggest-commit/SKILL.md` - moved from `claude/skills/suggest-commit/SKILL.md`
- `agents/skills/suggest-title/SKILL.md` - moved from `claude/skills/suggest-title/SKILL.md`
- `agents/agents/.gitkeep` - moved from `claude/agents/.gitkeep`

**Modify:**
- `claude/CLAUDE.md` - replace content with `@` import
- `dotfiles.yml` - add `agents` section, update `claude` section
- `bootstrap.sh` - add `~/.agents/` linking, remove skills/agents from claude section
- `README.md` - update structure tree

**Delete:**
- `claude/skills/suggest-commit/SKILL.md`
- `claude/skills/suggest-title/SKILL.md`
- `claude/agents/.gitkeep`

---

### Task 1: Create agents/ directory and move portable content

**Files:**
- Create: `agents/AGENTS.md`
- Create: `agents/skills/suggest-commit/SKILL.md`
- Create: `agents/skills/suggest-title/SKILL.md`
- Create: `agents/agents/.gitkeep`
- Delete: `claude/skills/suggest-commit/SKILL.md`
- Delete: `claude/skills/suggest-title/SKILL.md`
- Delete: `claude/agents/.gitkeep`

- [ ] **Step 1: Create agents/ directory structure**

```bash
mkdir -p agents/skills/suggest-commit agents/skills/suggest-title agents/agents
```

- [ ] **Step 2: Move skills from claude/ to agents/**

```bash
mv claude/skills/suggest-commit/SKILL.md agents/skills/suggest-commit/SKILL.md
mv claude/skills/suggest-title/SKILL.md agents/skills/suggest-title/SKILL.md
```

- [ ] **Step 3: Move agents/ subdir from claude/ to agents/**

```bash
mv claude/agents/.gitkeep agents/agents/.gitkeep
```

- [ ] **Step 4: Remove empty claude/skills/ and claude/agents/ directories**

```bash
rm -rf claude/skills claude/agents
```

- [ ] **Step 5: Create agents/AGENTS.md with content from claude/CLAUDE.md**

Write `agents/AGENTS.md` with the full current content of `claude/CLAUDE.md`:

```markdown
## Communication

- Say "I don't know" rather than guessing when uncertain.
- Ground factual claims with direct quotes from the source. If you can't find a supporting quote, retract the claim.
- For long documents (>20k tokens), extract relevant quotes before performing the task.
- If two things sound similar but might differ, say so - don't assert equivalence without verifying. When unsure, say "I'm not sure" or ask.
- Use simple dashes (-), never em-dashes (—).
- When asked to "add a rule" or "remember this rule", always add it to a CLAUDE.md file (repo-specific or global), never to memory.

## Git

- Never force push.
- Never add Co-Authored-By lines or any AI attribution to commit messages.
- Write commit messages in simple present imperative tense. The subject line should complete the sentence "This commit will…"
- Never use conventional commit style prefixes.
  - **Avoid:**
    - `feat: add dark mode support` - no prefixes
    - `fix(auth): resolve token expiry bug` - no prefixes or scope notation
    - `chore: update dependencies` - no prefixes
    - `Added dark mode support` - past tense, not imperative
    - `Adding dark mode support` - gerund, not imperative
  - **Prefer:**
    - `Add dark mode support`
    - `Fix token expiry bug in auth flow`
    - `Update dependencies`
    - `Remove deprecated API calls`
    - `Refactor settings page layout`

## Tool Usage

- Never truncate output from linters, test runners, or compilers. Errors and summaries appear at the end - using `head` hides them. If output is long, use `tail` to see the summary.
```

- [ ] **Step 6: Commit**

```bash
git add agents/ claude/skills claude/agents
git commit -m "Move portable skills and agents to tool-agnostic agents/ directory"
```

---

### Task 2: Update claude/CLAUDE.md to import AGENTS.md

**Files:**
- Modify: `claude/CLAUDE.md`

- [ ] **Step 1: Replace claude/CLAUDE.md content with @ import**

Replace the entire content of `claude/CLAUDE.md` with:

```markdown
@~/.agents/AGENTS.md
```

- [ ] **Step 2: Commit**

```bash
git add claude/CLAUDE.md
git commit -m "Replace CLAUDE.md content with @import to shared AGENTS.md"
```

---

### Task 3: Update dotfiles.yml

**Files:**
- Modify: `dotfiles.yml`

- [ ] **Step 1: Add agents section and update claude section**

Replace the full content of `dotfiles.yml` with:

```yaml
# Configuration used by bootstrap.sh

oh-my-zsh:
  zshrc: true
  # Note that the zshrc symlink also implicitly covers pointing to the zsh-custom directory.

git:
  gitconfig: true

markdownlint:
  config: true

vscode:
  settings: true
  extensions: true

iterm2:
  preferences: true

agents:
  settings: true
  agents: true
  skills: true

claude:
  settings: true
  commands: true
```

- [ ] **Step 2: Commit**

```bash
git add dotfiles.yml
git commit -m "Add agents section to dotfiles.yml; remove skills/agents from claude section"
```

---

### Task 4: Update bootstrap.sh

**Files:**
- Modify: `bootstrap.sh:155-178`

- [ ] **Step 1: Add agents linking section before the claude section**

Insert the following block before the `# --- claude ---` section (before line 155):

```bash
# --- agents (tool-agnostic) ---
if is_enabled '.agents.settings'; then
    info "Linking shared agent settings"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/AGENTS.md" "$HOME/.agents/AGENTS.md"
fi

if is_enabled '.agents.agents'; then
    info "Linking shared agents"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/agents" "$HOME/.agents/agents"
fi

if is_enabled '.agents.skills'; then
    info "Linking shared skills"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/skills" "$HOME/.agents/skills"
fi
```

- [ ] **Step 2: Update the claude section**

Replace the existing claude section (lines 155-178) with:

```bash
# --- claude ---
if is_enabled '.claude.settings'; then
    info "Linking Claude Code settings"
    for file in statusline-command.sh CLAUDE.md; do
        src="$DOTFILES_ROOT/claude/$file"
        [ -f "$src" ] || continue
        link_file "$src" "$HOME/.claude/$file"
    done
fi

if is_enabled '.claude.commands'; then
    info "Linking Claude Code commands"
    link_file "$DOTFILES_ROOT/claude/commands" "$HOME/.claude/commands"
fi
```

The agents and skills linking for `~/.claude/` is removed. It will be added back conditionally in Task 6 if Claude Code doesn't read from `~/.agents/` natively.

- [ ] **Step 3: Commit**

```bash
git add bootstrap.sh
git commit -m "Update bootstrap.sh to link agents/ to ~/.agents/"
```

---

### Task 5: Update README.md structure tree

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update the structure tree**

Replace the structure tree in README.md with:

```text
dotfiles/
├── dotfiles.yml                       # what bootstrap.sh should set up
├── bootstrap.sh                       # the installer
├── bin/*                              # global functions
├── brew/
│   └── Brewfile                       # brew bundle
├── zsh/
│   ├── zshrc.symlink                  → ~/.zshrc
│   ├── zshrc.local.symlink            → ~/.zshrc.local (machine-specific)
│   └── zsh-custom/                    → set and sourced via $ZSH_CUSTOM in .zshrc
│       ├── 00-paths-defaults.zsh      # base PATH setup
│       ├── 02-paths.local.zsh         # machine-specific paths
│       ├── 05-paths-additional.zsh    # extra PATH entries
│       ├── 10-flags.zsh               # shell flags
│       ├── 12-flags.local.zsh         # machine-specific flags
│       ├── 30-aliases.zsh             # shared aliases
│       ├── 31-aliases.local.zsh       # machine-specific aliases
│       ├── 60-prompt.zsh              # prompt config
│       └── themes/*                   # themes
├── git/
│   ├── gitconfig.symlink              → ~/.gitconfig
│   ├── gitconfig.local.symlink        → ~/.gitconfig.local (machine-specific)
│   ├── bin/*                          # git functions
│   └── hooks/*                        # git hooks
├── iterm2/
│   ├── com.googlecode.iterm2.plist    # loaded via iTerm2's custom folder pref
│   └── iterm-filter.sh                # git clean/smudge filter for the plist
├── markdownlint/
│   └── markdownlint.yml.symlink        → ~/.markdownlint.yml
├── vscode/
│   ├── settings.json                  → ~/Library/Application Support/Code/User/settings.json
│   ├── keybindings.json               → ~/Library/Application Support/Code/User/keybindings.json
│   └── extensions.txt                 # installed via `code --install-extension`
├── agents/
│   ├── AGENTS.md                      → ~/.agents/AGENTS.md (shared instructions)
│   ├── agents/*                       → ~/.agents/agents/
│   └── skills/*                       → ~/.agents/skills/
└── claude/
    ├── CLAUDE.md                      → ~/.claude/CLAUDE.md (imports AGENTS.md)
    ├── statusline-command.sh          → ~/.claude/statusline-command.sh
    └── commands/*                     → ~/.claude/commands/
```

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "Update README structure tree for agents/ migration"
```

---

### Task 6: Verify and fix Claude Code integration

This task is manual verification performed in the active Claude Code session.

- [ ] **Step 1: Remove stale symlinks**

Remove the old symlinks that pointed to the now-deleted `claude/skills` and `claude/agents`:

```bash
rm -f ~/.claude/skills ~/.claude/agents
```

- [ ] **Step 2: Run bootstrap.sh**

```bash
./bootstrap.sh
```

Verify output shows:
- `~/.agents/AGENTS.md` linked
- `~/.agents/agents/` linked
- `~/.agents/skills/` linked
- `~/.claude/CLAUDE.md` linked
- `~/.claude/commands/` linked
- `~/.claude/statusline-command.sh` linked

- [ ] **Step 3: Test @ import in CLAUDE.md**

Start a new Claude Code conversation or check that the current session picks up the AGENTS.md content through the `@` import. If the instructions (communication, git, tool usage) appear in context, the import works.

If `@` import fails, update `claude/CLAUDE.md` to:

```markdown
All instructions are in ~/.agents/AGENTS.md. Read and follow that file.
```

- [ ] **Step 4: Test skill resolution from ~/.agents/skills/**

Invoke `/suggest-title` to see if Claude Code finds the skill at `~/.agents/skills/suggest-title/SKILL.md`.

If it doesn't resolve, add these symlinks to the claude section of bootstrap.sh:

```bash
# Bridge ~/.claude/ to ~/.agents/ for tools that don't read ~/.agents/ natively
if is_enabled '.agents.skills'; then
    info "Bridging Claude Code skills to shared skills"
    link_file "$HOME/.agents/skills" "$HOME/.claude/skills"
fi

if is_enabled '.agents.agents'; then
    info "Bridging Claude Code agents to shared agents"
    link_file "$HOME/.agents/agents" "$HOME/.claude/agents"
fi
```

Then re-run bootstrap.sh and re-test.

- [ ] **Step 5: Commit any fixes**

If any fallback changes were needed, commit them:

```bash
git add bootstrap.sh claude/CLAUDE.md
git commit -m "Add fallback symlinks for Claude Code skill/agent resolution"
```
