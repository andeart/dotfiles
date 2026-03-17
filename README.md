# dotfiles by @andeart

This README is still WIP.

---

Structure

```text
dotfiles/
├── dotfiles.yml               # configuration
├── bootstrap.sh               # installer
├── zsh/
│   ├── zshrc.symlink          → ~/.zshrc
│   ├── custom/                → implicitly covered from $ZSH_CUSTOM through the .zshrc.
│   │   ├── aliases.zsh        
│   │   ├── themes/
│   │   │   └── *.zsh-theme
│   │   └── plugins/
│   │       └── */
├── git/
│   ├── gitconfig.symlink      → ~/.gitconfig
│   └── gitignore_global.symlink → ~/.gitignore_global
├── iterm2/
│   └── profile.json           # manual import or defaults write
├── vscode/
│   ├── settings.json          → ~/Library/Application Support/Code/User/
│   ├── keybindings.json       → ~/Library/Application Support/Code/User/
│   └── extensions.txt         # installed via script
├── claude/
│   └── ...                    → TBD. My statusline changes at least, to begin with.
└── brew/
    └── Brewfile               # brew bundle
```

- *.symlink handles anything destined for $HOME
- VS Code, iTerm2, and Claude Code configs go to app-specific paths — the bootstrap handles these explicitly since there's no
convention that would make them self-describing without being confusing
