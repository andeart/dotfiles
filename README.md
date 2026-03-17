# dotfiles by @andeart

Structure

```text
dotfiles/
├── dotfiles.yml               # configuration
├── bootstrap.sh               # installer
├── zsh/
│   ├── zshrc.symlink          → ~/.zshrc
│   ├── custom/
│   │   ├── aliases.zsh        → $ZSH_CUSTOM/aliases.zsh
│   │   ├── themes/
│   │   │   └── *.zsh-theme    → $ZSH_CUSTOM/themes/
│   │   └── plugins/
│   │       └── */             → $ZSH_CUSTOM/plugins/
├── git/
│   ├── gitconfig.symlink      → ~/.gitconfig
│   └── gitignore_global.symlink → ~/.gitignore_global
├── iterm2/
│   └── profile.json           # manual import or defaults write
├── vscode/
│   ├── settings.json          → ~/Library/Application Support/Code/User/
│   ├── keybindings.json       → ~/Library/Application Support/Code/User/
│   └── extensions.txt         # installed via script
├── claude-code/
│   └── ...                    → ~/.claude/
└── homebrew/
    └── Brewfile               # brew bundle
```

- *.symlink handles anything destined for $HOME
- zsh/custom/ mirrors the $ZSH_CUSTOM directory structure exactly, so the bootstrap can symlink its contents into place without
guessing
- VS Code, iTerm2, and Claude Code configs go to app-specific paths — the bootstrap handles these explicitly since there's no
convention that would make them self-describing without being confusing
