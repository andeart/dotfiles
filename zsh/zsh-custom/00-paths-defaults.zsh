export ANDROID_HOME=${HOME}/Library/Android/sdk
# Static default avoids a ~150ms $(brew --prefix) subprocess on every shell start.
# If my Homebrew prefix differs, override in 02-paths.local.zsh.
if [[ "$(uname -m)" == "arm64" ]]; then
  export BREW_PREFIX="/opt/homebrew"
else
  export BREW_PREFIX="/usr/local"
fi
