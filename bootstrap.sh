#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")" && pwd)"
DOTFILES_CONFIG="$REPO_ROOT/dotfiles.yml"
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"
VSCODE_USER="$HOME/Library/Application Support/Code/User"

info()    { printf "\r\033[00;34m•\033[0m %s\n" "$1"; }
success() { printf "\r    \033[00;32mOK\033[0m · %s\n" "$1"; }
fail()    { printf "\r    \033[0;31mFAIL\033[0m · %s\n" "$1"; echo ''; exit 1; }
warn()    { printf "\r    \033[00;33mWARN\033[0m · %s\n" "$1"; }

_failed_extensions=()

# Config file is required
if [ ! -f "$DOTFILES_CONFIG" ]; then
    fail "dotfiles.yml not found at $DOTFILES_CONFIG"
fi

# Pre-parse dotfiles.yml once and stash each flag in a dynamic variable
# (_dotfiles_flag_<sanitized-key>). is_enabled then resolves via bash's
# indirect expansion (${!var}) for O(1) lookups without forking yq per
# check. Associative arrays would be cleaner but require bash 4+, and
# macOS ships with bash 3.2. _dotfiles_flag_keys preserves document order
# for the plan log below.
_dotfiles_flag_keys=()
while IFS=$'\t' read -r section key val; do
    [ -z "$section" ] && continue
    full_key="$section.$key"
    var_name="_dotfiles_flag_${full_key//[^a-zA-Z0-9]/_}"
    printf -v "$var_name" '%s' "$val"
    _dotfiles_flag_keys+=("$full_key")
done < <(yq -r 'to_entries[] | .key as $section | .value | to_entries[] | [$section, .key, (.value | tostring)] | @tsv' "$DOTFILES_CONFIG" 2>/dev/null)

# Read a boolean value from dotfiles.yml. Returns 0 (true) or 1 (false).
is_enabled() {
    local key="${1#.}"
    local var_name="_dotfiles_flag_${key//[^a-zA-Z0-9]/_}"
    [ "${!var_name:-}" = "true" ]
}

# Check that all Brewfile dependencies are installed
if ! command -v brew &>/dev/null; then
    fail "Homebrew is required but not installed."
fi

BREWFILE="$REPO_ROOT/brew/Brewfile"
if [ -f "$BREWFILE" ]; then
    if brew bundle check --file="$BREWFILE" &>/dev/null; then
        success "All Brewfile dependencies already installed"
    else
        info "Brewfile has missing dependencies:"
        brew bundle check --file="$BREWFILE" --verbose || true
        echo ''
        read -rp "  Install missing Brewfile dependencies? (y/n) " confirm
        if [ "$confirm" = "y" ]; then
            if ! brew bundle install --file="$BREWFILE" --no-upgrade; then
                fail "Failed to install Brewfile dependencies."
            fi
            success "All Brewfile dependencies installed"
        else
            warn "Skipping Brewfile install"
        fi
    fi
fi

# Log the full bootstrap plan derived from dotfiles.yml
echo ''
info "Bootstrap plan (from dotfiles.yml):"
# Guarded against an empty array because bash 3.2 treats "${arr[@]}" as
# unbound under `set -u` when there are zero elements (a config with all
# flags commented out, for example).
if [ ${#_dotfiles_flag_keys[@]} -gt 0 ]; then
    for flag_key in "${_dotfiles_flag_keys[@]}"; do
        var_name="_dotfiles_flag_${flag_key//[^a-zA-Z0-9]/_}"
        if [ "${!var_name}" = "true" ]; then
            printf "    [  \033[00;32mON\033[0m ] %s\n" "$flag_key"
        else
            printf "    [ \033[00;31mOFF\033[0m ] %s\n" "$flag_key"
        fi
    done
fi
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

# --- agents-and-claude (file sync via dotfiles push) ---
if is_enabled '.agents-and-claude.sync'; then
    info "Syncing agents/claude files to live destinations"
    mkdir -p "$HOME/.dotfiles" "$HOME/.agents" "$HOME/.claude"
    if "$DOTFILES_ROOT/bin/dotfiles" push; then
        success "agents/claude files synced"
    else
        warn "dotfiles push reported issues - run 'dotfiles status' for details"
    fi
fi

# --- pre-commit hook installation ---
if command -v pre-commit &>/dev/null; then
    info "Installing pre-commit hooks"
    (cd "$DOTFILES_ROOT" && pre-commit install) >/dev/null
    success "pre-commit hooks installed"
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
