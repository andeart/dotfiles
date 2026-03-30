# Tool-agnostic agents/ migration

Move portable AI assistant configuration (instructions, skills, subagent definitions) out of the Claude-specific `claude/` directory into a new `agents/` directory, targeting `~/.agents/` on the machine. Claude-specific files (commands, statusline) stay in `claude/`.

## Motivation

Multiple tools (Claude Code, Codex, Cursor) converge on `~/.agents/skills/` as a shared skill location. Centralizing portable content there avoids duplication when adopting additional tools.

## Repo structure (after)

```text
dotfiles/
├── agents/                              # portable, tool-agnostic
│   ├── AGENTS.md                        # shared instructions (moved from claude/CLAUDE.md)
│   ├── agents/                          # subagent definitions
│   │   └── .gitkeep
│   └── skills/                          # portable skills
│       ├── suggest-commit/
│       │   └── SKILL.md
│       └── suggest-title/
│           └── SKILL.md
├── claude/                              # Claude-specific only
│   ├── CLAUDE.md                        # imports @~/.agents/AGENTS.md
│   ├── commands/                        # Claude slash commands
│   │   ├── create-skill.md
│   │   └── linear-create-issue.md
│   └── statusline-command.sh
```

Removed from `claude/`: `agents/`, `skills/`, and the instruction content from `CLAUDE.md`.

## Symlink targets

| Source (repo) | Target (machine) |
|---|---|
| `agents/AGENTS.md` | `~/.agents/AGENTS.md` |
| `agents/agents/` | `~/.agents/agents/` |
| `agents/skills/` | `~/.agents/skills/` |
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` |
| `claude/commands/` | `~/.claude/commands/` |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` |

Conditionally (if Claude Code doesn't read from `~/.agents/` natively):
- `~/.claude/skills -> ~/.agents/skills`
- `~/.claude/agents -> ~/.agents/agents`

## CLAUDE.md

```markdown
@~/.agents/AGENTS.md
```

Fallback if `@` import doesn't work:

```markdown
All instructions are in ~/.agents/AGENTS.md. Read and follow that file.
```

## AGENTS.md

Identical content to current `claude/CLAUDE.md` (communication, git, tool usage rules).

## dotfiles.yml

```yaml
agents:
  settings: true
  agents: true
  skills: true

claude:
  settings: true
  commands: true
```

## bootstrap.sh changes

- New `agents` section: create `~/.agents/` directory, link AGENTS.md, agents/, skills/
- Updated `claude` section: remove agents/skills linking, keep commands and Claude-specific files
- Conditional symlinks `~/.claude/skills -> ~/.agents/skills` and `~/.claude/agents -> ~/.agents/agents` if needed

## Verification (in-session)

1. Run bootstrap.sh to create all symlinks
2. Test `@` import - confirm Claude Code reads AGENTS.md instructions through it
3. Test skill resolution - invoke `/suggest-title` from `~/.agents/skills/`
4. If skill resolution fails from `~/.agents/`, add `~/.claude/skills -> ~/.agents/skills` symlink to bootstrap.sh and re-test
