# dotfiles

My environment, painstakingly curated over years I could have spent learning piano or something. You're welcome to poke around, steal ideas, or judge my aliases (silently).

The setup is macOS-only because I made choices in life and I'm living with them.

2026-03-16: I'm consolidating multiple machines/images so I'm using this opportunity to clean my dotfiles up. Things will keep moving around for a minute.

Updates on this repo tend to land late at night. I tinker with this after I've finished other coding projects.

## Getting started

```sh
# Install Homebrew dependencies first
brew bundle --file=brew/Brewfile

./bootstrap.sh
```

The bootstrap reads `dotfiles.yml` to figure out what to symlink or install. It'll pause before doing anything irreversible.

Some files have `.local` variants (with `.example` templates) for machine-specific config that shouldn't live in git, like paths that differ between machines, secrets, and such. The bootstrap will remind about these before it starts symlinking (I keep forgetting).

## Structure

```text
dotfiles/
├── dotfiles.yml                       # what bootstrap.sh should set up
├── bootstrap.sh                       # the installer
├── .github/
│   ├── dependabot.yml                 # weekly bumps for pinned action SHAs
│   └── workflows/
│       └── claude.yml                 # dispatches Claude Code on @claude mentions
├── bin/*                              # utility scripts
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
│       ├── 20-secrets.local.zsh       # machine-specific secrets
│       ├── 30-aliases.zsh             # shared aliases
│       └── 31-aliases.local.zsh       # machine-specific aliases
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
    ├── settings.json                  → ~/.claude/settings.json
    ├── statusline-command.sh          → ~/.claude/statusline-command.sh
    └── commands/*                     → ~/.claude/commands/
```

All the `→` locations represent symlinks.

### How linking works

- `*.symlink` files get linked to `$HOME` as dotfiles (so `gitconfig.symlink` becomes `~/.gitconfig`, etc). Straightforward.
- Some configs (VS Code, iTerm2, Claude Code, etc) go to app-specific paths, not `$HOME`. The bootstrap handles these explicitly.
- `*.local.*` files are for per-machine overrides. Each one has a `.example` template.
- The zsh-custom files are numbered because order matters when ZSH_CUSTOM is loaded by OMZ.

## The iTerm2 plist situation

Anyhow, the iTerm2 plist deserves a brief aside. It's a binary plist that iTerm2 rewrites constantly with transient state, which makes version control a bit of an adventure. I made a git clean/smudge filter (`iterm-filter.sh`) that strips noise on commit and restores it on checkout. It also swaps `$HOME` with a placeholder so the plist isn't hardcoded to one user's home directory. Did I overengineer it? Maybe. Did the diff noise bother me enough to write a filter? One hundo.
