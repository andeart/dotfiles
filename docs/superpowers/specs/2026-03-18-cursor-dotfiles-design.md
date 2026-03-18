# Cursor Dotfiles Integration Design

**Linear:** BYA-90
**Date:** 2026-03-18
**Status:** Approved

---

## Goal

Switch to Cursor as the primary editor and version-control its configuration in dotfiles, mirroring the existing VS Code pattern. VS Code support remains unchanged.

---

## Repository Structure

A new `cursor/` directory is added alongside `vscode/`:

```
cursor/
  keybindings.json  ← symlink → ../vscode/keybindings.json  (VS Code is source of truth)
  settings.json     ← symlink → ../vscode/settings.json      (VS Code is source of truth)
  extensions.txt    ← own file (reviewed and finalized after opening Cursor IDE)
```

Both `cursor/keybindings.json` and `cursor/settings.json` are committed to the repo as relative symlinks. This design was chosen after reconciling the two files post-review: the settings were identical enough (and both editors silently ignore unknown keys) that a single shared file is cleaner than maintaining two in sync. Any future Cursor-specific setting can be added to `vscode/settings.json` — VS Code will ignore unknown `cursor.*` keys.

These in-repo symlinks must be created manually and staged with `git add` — they are separate from the symlinks `bootstrap.sh` creates into `~/Library/Application Support/Cursor/User/`. Git tracks them as symlinks (mode 120000); macOS follows the full chain from the Cursor user directory through to the VS Code file.

---

## bootstrap.sh

A new `cursor` block is added, structured identically to the existing `vscode` block:

**Settings symlinking** (when `.cursor.settings` is enabled):
- `cursor/settings.json` → `~/Library/Application Support/Cursor/User/settings.json`
- `cursor/keybindings.json` → `~/Library/Application Support/Cursor/User/keybindings.json`

**Extensions install** (when `.cursor.extensions` is enabled):
- Iterate `cursor/extensions.txt` and run `cursor --install-extension <ext>` for each line
- Guard with `command -v cursor` (same pattern as the `code` guard for VS Code)

---

## dotfiles.yml

```yaml
cursor:
  settings: true
  extensions: true
```

Added after the `vscode` section, mirroring it exactly.

---

## Default Editor

Three env vars added to `zsh/zsh-custom/10-flags.zsh` (alongside the existing `PAGER`/`GIT_PAGER` exports):

```sh
export EDITOR="cursor --wait"
export VISUAL="cursor --wait"
export GIT_EDITOR="cursor --wait"
```

`--wait` blocks the shell until the Cursor window is closed, which is required for `git commit`, `git rebase -i`, etc.

---

## Symlink Chains

```
~/Library/Application Support/Cursor/User/keybindings.json
  → $DOTFILES_ROOT/cursor/keybindings.json        (repo symlink, linked by bootstrap.sh)
    → $DOTFILES_ROOT/vscode/keybindings.json       (source of truth)

~/Library/Application Support/Cursor/User/settings.json
  → $DOTFILES_ROOT/cursor/settings.json           (repo symlink, linked by bootstrap.sh)
    → $DOTFILES_ROOT/vscode/settings.json          (source of truth)
```

Editing either `vscode/` file automatically propagates to Cursor with no further action.

---

## Out of Scope

- Removing or deprecating VS Code support (remains fully functional)
- Cursor Rules files or project-level Cursor config
- Any settings not surfaced in the Cursor IDE settings UI

---

## Pre-Implementation Requirement

Per the Linear issue: **open Cursor and manually review all settings in the IDE before finalizing `cursor/settings.json` and `cursor/extensions.txt`**. The implementation plan should include this as a blocking manual step.
