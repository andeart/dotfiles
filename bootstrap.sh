#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_CONFIG="$REPO_ROOT/dotfiles.yml"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"
CURSOR_USER="$HOME/Library/Application Support/Cursor/User"

info()    { printf "\r\033[00;34m•\033[0m %s\n" "$1"; }
success() { printf "\r    \033[00;32mOK\033[0m · %s\n" "$1"; }
fail()    { printf "\r    \033[0;31mFAIL\033[0m · %s\n" "$1"; echo ''; exit 1; }

# Read a boolean value from dotfiles.yml. Returns 0 (true) or 1 (false).
is_enabled() {
    local key="$1"
    local val
    val=$(yq "$key" "$DOTFILES_CONFIG" 2>/dev/null)
    [ "$val" = "true" ]
}

# Config file is required
if [ ! -f "$DOTFILES_CONFIG" ]; then
    fail "dotfiles.yml not found at $DOTFILES_CONFIG"
fi

# Check that all Brewfile dependencies are installed
if ! command -v brew &>/dev/null; then
    fail "Homebrew is required but not installed."
fi

BREWFILE="$REPO_ROOT/brew/Brewfile"
if [ -f "$BREWFILE" ]; then
    info "Checking Brewfile dependencies"
    if ! brew bundle check --file="$BREWFILE" --verbose; then
        fail "Missing Brewfile dependencies. Run: brew bundle --file=$BREWFILE"
    fi
    success "All Brewfile dependencies installed"
fi

# Log the full bootstrap plan derived from dotfiles.yml
echo ''
info "Bootstrap plan (from dotfiles.yml):"
while IFS=$'\t' read -r section key val; do
    if [ "$val" = "true" ]; then
        printf "    [  \033[00;32mON\033[0m ] %s.%s\n" "$section" "$key"
    else
        printf "    [ \033[00;31mOFF\033[0m ] %s.%s\n" "$section" "$key"
    fi
done < <(yq 'to_entries[] | .key as $section | .value | to_entries[] | [$section, .key, (.value | tostring)] | join("\t")' "$DOTFILES_CONFIG" 2>/dev/null)
echo ''

# Remind user to set up .local files before symlinking begins
info "Before continuing, ensure the following .local files exist and are up to date:"
find -H "$REPO_ROOT" -maxdepth 3 -name '*.local.symlink.example' -not -path '*/.git/*' | while read -r example; do
    local_file="${example%.example}"
    relative="${local_file#$REPO_ROOT/}"
    printf "    %s\n" "$relative"
done
echo ''
read -rp "  Ready to continue? (y/n) " confirm
[ "$confirm" = "y" ] || { echo "Aborted."; exit 0; }
echo ''

# Verify DOTFILES_ROOT will be available at shell startup
if ! grep -q 'export DOTFILES_ROOT=' "$REPO_ROOT/zsh/zshrc.local.symlink" 2>/dev/null; then
    fail "zshrc.local.symlink must export DOTFILES_ROOT (see zshrc.local.symlink.example)"
fi

# From here on, use DOTFILES_ROOT as the canonical name
DOTFILES_ROOT="$REPO_ROOT"

link_file() {
    local src="$1" dst="$2"

    if [ -f "$dst" ] || [ -d "$dst" ] || [ -L "$dst" ]; then
        # already points to the right place
        if [ "$(readlink "$dst")" = "$src" ]; then
            success "already linked $dst"
            return
        fi

        read -rp "File exists: $dst (b)ackup, (s)kip, (o)verwrite? " action
        case "$action" in
            o) rm -rf "$dst" ;;
            b) mv "$dst" "${dst}.backup"; success "backed up $dst" ;;
            s) success "skipped $dst"; return ;;
        esac
    fi

    ln -s "$src" "$dst"
    success "linked $src → $dst"
}

# --- git ---
if is_enabled '.git.gitconfig'; then
    info "Linking git config"
    for src in "$DOTFILES_ROOT"/git/*gitconfig*.symlink; do
        [ -f "$src" ] || continue
        dst="$HOME/.$(basename "$src" '.symlink')"
        link_file "$src" "$dst"
    done
fi

# --- oh-my-zsh: zshrc ---
if is_enabled '.oh-my-zsh.zshrc'; then
    info "Linking zshrc"
    for src in "$DOTFILES_ROOT"/zsh/*zshrc*.symlink; do
        [ -f "$src" ] || continue
        dst="$HOME/.$(basename "$src" '.symlink')"
        link_file "$src" "$dst"
    done
fi

# --- vscode ---
if is_enabled '.vscode.settings'; then
    info "Linking VS Code settings"
    for file in settings.json keybindings.json; do
        src="$DOTFILES_ROOT/vscode/$file"
        [ -f "$src" ] || continue
        link_file "$src" "$VSCODE_USER/$file"
    done
fi

if is_enabled '.vscode.extensions'; then
    info "Installing VS Code extensions"
    if command -v code &>/dev/null; then
        while IFS= read -r ext; do
            code --install-extension "$ext" --force 2>/dev/null && success "installed $ext" || fail "failed to install $ext"
        done < "$DOTFILES_ROOT/vscode/extensions.txt"
    else
        info "VS Code CLI not found — skipping extensions install"
    fi
fi

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

# --- claude ---
if is_enabled '.claude.settings'; then
    info "Linking Claude Code settings"
    for file in settings.json statusline-command.sh CLAUDE.md; do
        src="$DOTFILES_ROOT/claude/$file"
        [ -f "$src" ] || continue
        link_file "$src" "$HOME/.claude/$file"
    done
fi

# --- iterm2 ---
if is_enabled '.iterm2.preferences'; then
    info "Configuring iTerm2 to load preferences from dotfiles"

    # Set up git clean/smudge filter for the iTerm2 plist (repo-local config).
    # clean: strips transient state and replaces $HOME with __HOME__ on git add/diff.
    # smudge: resolves __HOME__ back to $HOME and converts to binary on checkout.
    git -C "$DOTFILES_ROOT" config filter.iterm-plist.clean "$DOTFILES_ROOT/iterm2/iterm-filter.sh clean"
    git -C "$DOTFILES_ROOT" config filter.iterm-plist.smudge "$DOTFILES_ROOT/iterm2/iterm-filter.sh smudge"
    success "git iterm-plist filter configured"

    defaults write com.googlecode.iterm2 PrefsCustomFolder -string "$DOTFILES_ROOT/iterm2"
    defaults write com.googlecode.iterm2 LoadPrefsFromCustomFolder -bool true
    success "iTerm2 will load preferences from $DOTFILES_ROOT/iterm2"
fi

echo ''
success "All done!"
