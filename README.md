# dotfiles by @andeart

This README is still WIP.

TODO:

- Fix brewfile with common deps from both my machines

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
│   └── com.googlecode.iterm2.plist  # loaded via iTerm2's "Load preferences from custom folder"
├── vscode/
│   ├── settings.json          → ~/Library/Application Support/Code/User/settings.json
│   ├── keybindings.json       → ~/Library/Application Support/Code/User/keybindings.json
│   └── extensions.txt         # installed via `code --install-extension`
├── claude/
│   ├── settings.json          → ~/.claude/settings.json
│   ├── statusline-command.sh  → ~/.claude/statusline-command.sh
│   └── CLAUDE.md              → ~/.claude/CLAUDE.md
└── brew/
    └── Brewfile               # brew bundle
```

- *.symlink handles anything destined for $HOME
- VS Code, iTerm2, and Claude Code configs go to app-specific paths — the bootstrap handles these explicitly since there's no
convention that would make them self-describing without being confusing
