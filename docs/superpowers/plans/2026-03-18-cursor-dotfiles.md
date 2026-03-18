# Cursor Dotfiles Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add Cursor as a version-controlled editor in dotfiles, mirroring the VS Code pattern, with keybindings shared via symlink and Cursor set as the default system editor.

**Architecture:** A new `cursor/` directory holds `settings.json`, `extensions.txt`, and a repo-internal symlink for `keybindings.json` pointing to `vscode/keybindings.json`. `bootstrap.sh` gains a `cursor` block that symlinks config into `~/Library/Application Support/Cursor/User/` and installs extensions via `cursor --install-extension`. Three env vars in `10-flags.zsh` make Cursor the default editor.

**Tech Stack:** bash, zsh, macOS symlinks, Cursor CLI (`cursor`), yq (already a Brewfile dep)

---

## File Map

| File | Action | Responsibility |
|------|--------|----------------|
| `cursor/settings.json` | Create | Cursor general + AI-specific settings |
| `cursor/extensions.txt` | Create | Cursor extensions list |
| `cursor/keybindings.json` | Create (symlink) | Points to `../vscode/keybindings.json` |
| `dotfiles.yml` | Modify | Add `cursor.settings` and `cursor.extensions` toggles |
| `bootstrap.sh` | Modify | Add cursor symlink + extension install block |
| `zsh/zsh-custom/10-flags.zsh` | Modify | Export `EDITOR`, `VISUAL`, `GIT_EDITOR` |

---

## Task 1: Manual review gate — open Cursor and audit settings

> ⚠️ This task is a blocking manual step. Do not proceed until it is done.

**Files:** none

- [ ] **Step 1: Open Cursor and review all settings**

  Open Cursor → `Cmd+,` → go through every section (Editor, AI, Features, etc.).
  Decide for each setting:
  - Is it the default? → skip it (don't track)
  - Is it a preference that should follow you to any machine? → include in `cursor/settings.json`
  - Is it machine-local (e.g., a path to a local binary)? → do not track

- [ ] **Step 2: Review installed extensions**

  In Cursor, open the Extensions panel and list what's installed.
  Cross-reference with `vscode/extensions.txt`:

  ```
  cat vscode/extensions.txt
  ```

  Decide for each extension whether it should be in `cursor/extensions.txt`.
  Note: some VS Code marketplace extensions are not available in Cursor's marketplace — verify before including.

- [ ] **Step 3: Note down your decisions**

  Keep a mental or scratch-pad list of:
  - Settings to include in `cursor/settings.json`
  - Extensions to include in `cursor/extensions.txt`

  You'll use these in Task 2.

---

## Task 2: Create `cursor/settings.json` and `cursor/extensions.txt`

**Files:**
- Create: `cursor/settings.json`
- Create: `cursor/extensions.txt`

- [ ] **Step 1: Create `cursor/settings.json`**

  Based on your manual review in Task 1, create this file. At minimum it should include
  the settings from `vscode/settings.json` that apply to Cursor, plus any Cursor-specific
  settings (AI model, features, etc.).

  Start from the existing VS Code settings as a base — most will transfer directly:

  ```bash
  cat vscode/settings.json
  ```

  Create `cursor/settings.json` with your chosen settings. Example structure:

  ```json
  {
      "editor.wordWrap": "on",
      "editor.renderWhitespace": "all",
      "workbench.colorTheme": "GitHub Dark Default",
      "cursor.aiModel": "claude-sonnet-4-6"
      // ... other settings from your review
  }
  ```

- [ ] **Step 2: Create `cursor/extensions.txt`**

  One extension ID per line. Based on your review in Task 1:

  ```
  # cursor/extensions.txt
  github.github-vscode-theme
  miguelsolorio.symbols
  # ... other extensions from your review
  ```

- [ ] **Step 3: Verify the files are valid JSON / plain text**

  ```bash
  python3 -m json.tool cursor/settings.json > /dev/null && echo "valid JSON"
  wc -l cursor/extensions.txt
  ```

  Expected: `valid JSON` and a line count matching the number of extensions you chose.

- [ ] **Step 4: Commit**

  ```bash
  git add cursor/settings.json cursor/extensions.txt
  git commit -m "Add cursor/settings.json and cursor/extensions.txt"
  ```

---

## Task 3: Create the in-repo keybindings symlink

**Files:**
- Create: `cursor/keybindings.json` (symlink)

- [ ] **Step 1: Create the relative symlink**

  From the repo root:

  ```bash
  ln -s ../vscode/keybindings.json cursor/keybindings.json
  ```

- [ ] **Step 2: Verify the symlink resolves correctly**

  ```bash
  ls -la cursor/keybindings.json
  # Expected: cursor/keybindings.json -> ../vscode/keybindings.json

  cat cursor/keybindings.json | head -5
  # Expected: first few lines of vscode/keybindings.json
  ```

- [ ] **Step 3: Verify git sees it as a symlink (not a file)**

  ```bash
  git ls-files --stage cursor/keybindings.json
  # Expected: 120000 <hash> 0	cursor/keybindings.json
  # 120000 = symlink mode in git
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add cursor/keybindings.json
  git commit -m "Add cursor/keybindings.json as symlink to vscode/keybindings.json"
  ```

---

## Task 4: Add `cursor` section to `dotfiles.yml`

**Files:**
- Modify: `dotfiles.yml`

- [ ] **Step 1: Add the cursor section**

  Open `dotfiles.yml`. After the `vscode:` block, add:

  ```yaml
  cursor:
    settings: true
    extensions: true
  ```

  The full relevant portion should look like:

  ```yaml
  vscode:
    settings: true
    extensions: true

  cursor:
    settings: true
    extensions: true
  ```

- [ ] **Step 2: Verify yq can parse it**

  ```bash
  yq '.cursor.settings' dotfiles.yml
  # Expected: true

  yq '.cursor.extensions' dotfiles.yml
  # Expected: true
  ```

- [ ] **Step 3: Commit**

  ```bash
  git add dotfiles.yml
  git commit -m "Add cursor toggles to dotfiles.yml"
  ```

---

## Task 5: Add `cursor` block to `bootstrap.sh`

**Files:**
- Modify: `bootstrap.sh`

The `bootstrap.sh` currently defines `VSCODE_USER` near the top and has a `# --- vscode ---` block. Mirror this pattern exactly for Cursor.

- [ ] **Step 1: Add the `CURSOR_USER` variable**

  Near the top of `bootstrap.sh`, after the `VSCODE_USER` line (line 7), add:

  ```bash
  CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
  ```

  The top section should now read:

  ```bash
  VSCODE_USER="$HOME/Library/Application Support/Code/User"
  CURSOR_USER="$HOME/Library/Application Support/Cursor/User"
  ```

- [ ] **Step 2: Add the cursor block**

  After the closing `fi` of the `# --- vscode ---` extensions block (currently ends around line 133),
  add:

  ```bash
  # --- cursor ---
  if is_enabled '.cursor.settings'; then
      info "Linking Cursor settings"
      for file in settings.json keybindings.json; do
          src="$DOTFILES_ROOT/cursor/$file"
          [ -f "$src" ] || [ -L "$src" ] || continue
          link_file "$src" "$CURSOR_USER/$file"
      done
  fi

  if is_enabled '.cursor.extensions'; then
      info "Installing Cursor extensions"
      if command -v cursor &>/dev/null; then
          while IFS= read -r ext; do
              [[ "$ext" =~ ^# ]] || [ -z "$ext" ] && continue
              cursor --install-extension "$ext" --force 2>/dev/null && success "installed $ext" || fail "failed to install $ext"
          done < "$DOTFILES_ROOT/cursor/extensions.txt"
      else
          info "Cursor CLI not found — skipping extensions install"
      fi
  fi
  ```

  Note the `-f "$src" || -L "$src"` guard: this handles both regular files (`settings.json`)
  and symlinks (`keybindings.json`) correctly. The VS Code block only uses `-f`, which would
  silently skip symlinks.

- [ ] **Step 3: Dry-run verify the script parses without errors**

  ```bash
  bash -n bootstrap.sh && echo "syntax OK"
  # Expected: syntax OK
  ```

- [ ] **Step 4: Verify the Cursor user directory exists (create it if not)**

  ```bash
  ls "$HOME/Library/Application Support/Cursor/User/"
  # If it doesn't exist, open Cursor once to initialize it, then re-check.
  ```

- [ ] **Step 5: Run bootstrap and verify Cursor symlinks**

  ```bash
  bash bootstrap.sh
  # Answer prompts as appropriate (skip or overwrite for Cursor files)
  ```

  Then verify:

  ```bash
  ls -la "$HOME/Library/Application Support/Cursor/User/settings.json"
  # Expected: symlink → $DOTFILES_ROOT/cursor/settings.json

  ls -la "$HOME/Library/Application Support/Cursor/User/keybindings.json"
  # Expected: symlink → $DOTFILES_ROOT/cursor/keybindings.json

  # Follow the full chain for keybindings:
  cat "$HOME/Library/Application Support/Cursor/User/keybindings.json" | head -3
  # Expected: first 3 lines of vscode/keybindings.json
  ```

- [ ] **Step 6: Commit**

  ```bash
  git add bootstrap.sh
  git commit -m "Add cursor block to bootstrap.sh"
  ```

---

## Task 6: Set Cursor as default editor in `10-flags.zsh`

**Files:**
- Modify: `zsh/zsh-custom/10-flags.zsh`

- [ ] **Step 1: Add editor exports**

  Open `zsh/zsh-custom/10-flags.zsh`. After the existing `GIT_PAGER=""` line, add:

  ```bash
  export EDITOR="cursor --wait"
  export VISUAL="cursor --wait"
  export GIT_EDITOR="cursor --wait"
  ```

  The bottom of the file should now look like:

  ```bash
  export PAGER='less'
  export LESS='-R'
  export GIT_PAGER=""

  export EDITOR="cursor --wait"
  export VISUAL="cursor --wait"
  export GIT_EDITOR="cursor --wait"
  ```

- [ ] **Step 2: Reload zsh and verify**

  ```bash
  source ~/.zshrc
  echo $EDITOR
  # Expected: cursor --wait

  echo $GIT_EDITOR
  # Expected: cursor --wait
  ```

- [ ] **Step 3: Verify git uses Cursor**

  In any git repo, run:

  ```bash
  git var GIT_EDITOR
  # Expected: cursor --wait
  ```

- [ ] **Step 4: Commit**

  ```bash
  git add zsh/zsh-custom/10-flags.zsh
  git commit -m "Set Cursor as default editor (EDITOR, VISUAL, GIT_EDITOR)"
  ```
