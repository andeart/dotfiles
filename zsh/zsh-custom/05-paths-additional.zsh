# Rust - only source if installed so shells still start cleanly without cargo.
[ -r "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

# Ruby gems (CocoaPods, etc.)
export GEM_HOME="${HOME}/.gem"

# ---- PATH ----
export PATH="${DOTFILES_ROOT}/bin:${PATH}"
export PATH="${DOTFILES_ROOT}/git/bin:${PATH}"
export PATH="${HOME}/.pub-cache/bin:${PATH}"
export PATH="${GEM_HOME}/bin:${PATH}"
export PATH="${HOME}/.local/bin:${PATH}"
export PATH="${BREW_PREFIX}/opt/ruby/bin:${PATH}"
# ^ All lines above are PREFIXED to the default PATH, with lower lines being earlier in the final PATH.
# ---- default PATH divider ----
# v All lines below are SUFFIXED to the default PATH, with lower lines being later in the final PATH.
export PATH="${PATH}:${ANDROID_HOME}/tools"
export PATH="${PATH}:${ANDROID_HOME}/platform-tools"
export PATH="${PATH}:${ANDROID_HOME}/cmdline-tools/latest/bin"
export PATH="${PATH}:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
export PATH="${PATH}:${HOME}/Library/Application Support/JetBrains/Toolbox/scripts"
