#!/bin/bash
set -e

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_CONFIG="$REPO_ROOT/dotfiles.yml"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"

info()    { printf "\r\033[00;34m•\033[0m %s\n" "$1"; }
success() { printf "\r    \033[00;32mOK\033[0m · %s\n" "$1"; }
fail()    { printf "\r    \033[0;31mFAIL\033[0m · %s\n" "$1"; echo ''; exit 1; }
warn()    { printf "\r    \033[00;33mWARN\033[0m · %s\n" "$1"; }

_failed_extensions=()

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
    info "Installing missing Brewfile dependencies"
    if ! brew bundle install --file="$BREWFILE" --no-upgrade; then
        fail "Failed to install Brewfile dependencies."
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
find -H "$REPO_ROOT" -maxdepth 3 -name '*.local*.example' -not -path '*/.git/*' | while read -r example; do
    local_file="${example%.example}"
    relative="${local_file#$REPO_ROOT/}"
    printf "    %s\n" "$relative"
done
echo ''
read -rp "  Ready to continue? (y/n) " confirm
[ "$confirm" = "y" ] || { echo "Aborted."; exit 0; }
echo ''

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
            b) mv "$dst" "${dst}.backup.$(date +%Y%m%d%H%M%S)"; success "backed up $dst" ;;
            s) success "skipped $dst"; return ;;
        esac
    fi

    ln -s "$src" "$dst"
    success "linked $src → $dst"
}

# --- oh-my-zsh: zshrc ---
if is_enabled '.oh-my-zsh.zshrc'; then
    info "Linking zshrc"
    for src in "$REPO_ROOT"/zsh/*zshrc*.symlink; do
        [ -f "$src" ] || continue
        dst="$HOME/.$(basename "$src" '.symlink')"
        link_file "$src" "$dst"
    done
fi

# Verify DOTFILES_ROOT is exported by the shell config. This is required by other
# dotfiles configs (e.g. Claude settings, git hooks) that reference $DOTFILES_ROOT
# at shell startup outside of this script's scope. If this fails, create
# zsh/zsh-custom/02-paths.local.zsh from the .example file and export DOTFILES_ROOT.
if [ -f "$HOME/.zshrc" ]; then
    if ! zsh -c 'source ~/.zshrc 2>/dev/null && [ -n "$DOTFILES_ROOT" ]' 2>/dev/null; then
        fail "DOTFILES_ROOT is not set. Create zsh/zsh-custom/02-paths.local.zsh from the .example file and export DOTFILES_ROOT before re-running."
    fi
fi

# Use the repo root as the canonical DOTFILES_ROOT for this script.
DOTFILES_ROOT="$REPO_ROOT"

# --- git ---
if is_enabled '.git.gitconfig'; then
    info "Linking git config"
    for src in "$DOTFILES_ROOT"/git/*gitconfig*.symlink; do
        [ -f "$src" ] || continue
        dst="$HOME/.$(basename "$src" '.symlink')"
        link_file "$src" "$dst"
    done
fi

# --- markdownlint ---
if is_enabled '.markdownlint.config'; then
    info "Linking markdownlint config"
    for src in "$DOTFILES_ROOT"/markdownlint/*.symlink; do
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
            [[ "$ext" =~ ^# ]] && continue
            [ -z "$ext" ] && continue
            code --install-extension "$ext" --force 2>/dev/null && success "installed $ext" || { warn "failed to install $ext"; _failed_extensions+=("$ext"); }
        done < "$DOTFILES_ROOT/vscode/extensions.txt"
    else
        info "VS Code CLI not found - skipping extensions install"
    fi
fi

# --- agents (tool-agnostic) ---
if is_enabled '.agents.settings'; then
    info "Linking shared agent settings"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/AGENTS.md" "$HOME/.agents/AGENTS.md"
fi

if is_enabled '.agents.agents'; then
    info "Linking shared agents"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/agents" "$HOME/.agents/agents"
fi

if is_enabled '.agents.skills'; then
    info "Linking shared skills"
    mkdir -p "$HOME/.agents"
    link_file "$DOTFILES_ROOT/agents/skills" "$HOME/.agents/skills"
fi

# --- claude ---
if is_enabled '.claude.settings'; then
    info "Linking Claude Code settings"
    for file in statusline-command.sh CLAUDE.md; do
        src="$DOTFILES_ROOT/claude/$file"
        [ -f "$src" ] || continue
        link_file "$src" "$HOME/.claude/$file"
    done
fi

if is_enabled '.claude.commands'; then
    info "Linking Claude Code commands"
    link_file "$DOTFILES_ROOT/claude/commands" "$HOME/.claude/commands"
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
if [ ${#_failed_extensions[@]} -gt 0 ]; then
    warn "The following VS Code extensions failed to install:"
    for ext in "${_failed_extensions[@]}"; do
        printf "    %s\n" "$ext"
    done
    echo ''
fi
success "All done!"
