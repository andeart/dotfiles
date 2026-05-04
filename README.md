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
├── .markdownlint.yml                  → markdownlint/markdownlint.yml.symlink (in-repo .yml needed by pre-commit)
├── .yamllint.yml                      # yamllint config, used by pre-commit and CI
├── .github/
│   ├── dependabot.yml                 # weekly bumps for pinned action SHAs
│   └── workflows/
│       ├── claude.yml                 # dispatches Claude Code on @claude mentions
│       └── lint-and-test.yml          # runs pre-commit hooks on push and PRs to main
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
├── markdownlint/
│   └── markdownlint.yml.symlink        → ~/.markdownlint.yml
├── vscode/
│   ├── settings.json                  → ~/Library/Application Support/Code/User/settings.json
│   ├── keybindings.json               → ~/Library/Application Support/Code/User/keybindings.json
│   └── extensions.txt                 # installed via `code --install-extension`
├── agents/
│   ├── AGENTS.md                      # synced to ~/.agents/AGENTS.md
│   └── skills/*                       # synced to ~/.agents/skills/ and ~/.claude/skills/
└── claude/
    ├── CLAUDE.md                      # synced to ~/.claude/CLAUDE.md
    ├── settings.json                  # synced to ~/.claude/settings.json
    └── statusline-command.sh          # synced to ~/.claude/statusline-command.sh
```

The `agents/` and `claude/` subtrees are no longer symlinked - they're materialised by `bin/dotfiles push`. See "Why I dropped symlinks for agents/ and claude/" below for the why and "Editing claude / agents files" for the workflow.

### How linking works

- `*.symlink` files get linked to `$HOME` as dotfiles (so `gitconfig.symlink` becomes `~/.gitconfig`, etc). Straightforward.
- Some configs (VS Code, Claude Code, etc) go to app-specific paths, not `$HOME`. The bootstrap handles these explicitly.
- `*.local.*` files are for per-machine overrides. Each one has a `.example` template.
- The zsh-custom files are numbered because order matters when ZSH_CUSTOM is loaded by OMZ.

## Why I dropped symlinks for agents/ and claude/

Claude Code's permission allow rules require both the literal requested path and the resolved symlink target to match. With `~/.claude/skills` (or `~/.agents/skills`, etc.) symlinked into this repo, the resolved target became `/Users/anuragdevanapally/code/dotfiles/...` - a per-machine absolute path. So a clean rule like `Read(~/.agents/AGENTS.md)` couldn't fully match unless I also listed my machine path, which is a non-starter for committing to a public repo.

Removing those symlinks lets a single tilde-rooted rule do the work on every machine I bootstrap. The trade-off is that `~/.claude` and `~/.agents` are now real files maintained by `bin/dotfiles`, not free symlinks - but `bin/dotfiles` handles both directions and a pre-commit hook captures any external drift before it can disappear, so the workflow stays close to what it was.

If future-me is reading this and thinking "let me just re-symlink this to be tidier" - please don't. The point is precisely that they aren't symlinks. The pre-commit hook plus `dotfiles push` is doing the job.

## Editing claude / agents files

The dotfiles repo is the source of truth. The flow:

- Edit files under `agents/` or `claude/` in this repo as usual.
- Run `dotfiles push` to mirror them out to `~/.agents` and `~/.claude`.
- If an external tool (e.g. a Claude plugin install) changes a live file, you'll see it next time you run `dotfiles status` or commit. The pre-commit hook auto-stages live drift into your commit so the repo can't silently fall behind.
- `dotfiles freeze` (the existing umbrella) now also captures drift back from `~/.agents` and `~/.claude` if you want to do it explicitly outside of a commit.
- Conflicts (both sides edited a file in incompatible ways) abort with a clear message; resolve manually then re-run.
