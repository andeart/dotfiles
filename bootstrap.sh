#!/bin/bash
set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_CONFIG="$DOTFILES_ROOT/dotfiles.yml"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"

# Config file is required
if [ ! -f "$DOTFILES_CONFIG" ]; then
    echo "Error: dotfiles.yml not found at $DOTFILES_CONFIG"
    exit 1
fi

# Check for yq
if ! command -v yq &>/dev/null; then
    echo "Error: yq is required but not installed. Install it with: brew install yq"
    exit 1
fi

# Read a boolean value from dotfiles.yml. Returns 0 (true) or 1 (false).
is_enabled() {
    local key="$1"
    local val
    val=$(yq "$key" "$DOTFILES_CONFIG" 2>/dev/null)
    [ "$val" = "true" ]
}

info()    { printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"; }
success() { printf "\r  [ \033[00;32mOK\033[0m ] %s\n" "$1"; }
fail()    { printf "\r  [\033[0;31mFAIL\033[0m] %s\n" "$1"; echo ''; exit 1; }

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

echo ''
success "All done!"
