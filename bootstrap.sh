#!/bin/bash
set -e

DOTFILES_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_CONFIG="$DOTFILES_ROOT/dotfiles.yml"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"

info()    { printf "\r  [ \033[00;34m..\033[0m ] %s\n" "$1"; }
success() { printf "\r  [ \033[00;32mOK\033[0m ] %s\n" "$1"; }
fail()    { printf "\r  [\033[0;31mFAIL\033[0m] %s\n" "$1"; echo ''; exit 1; }

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

BREWFILE="$DOTFILES_ROOT/brew/Brewfile"
if [ -f "$BREWFILE" ]; then
    info "Checking Brewfile dependencies"
    if ! brew bundle check --file="$BREWFILE" &>/dev/null; then
        fail "Missing Brewfile dependencies. Run: brew bundle --file=$BREWFILE"
    fi
    success "All Brewfile dependencies installed"
fi

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

echo ''
success "All done!"
