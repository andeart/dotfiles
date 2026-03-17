export ANDROID_HOME=/Users/$USER/Library/Android/sdk

# ---- PATH ----
export PATH="$HOME/.pub-cache/bin:$PATH"
export PATH="$HOME/.local/bin:$PATH"
export PATH="$HOME/code/flutter/bin:$PATH"
export PATH="$HOME/code/protoc/bin:$PATH"
export PATH="$HOME/code/protoc/include:$PATH"
export PATH="/opt/homebrew/lib/ruby/gems/3.4.0/bin:$PATH"
export PATH="/opt/homebrew/opt/ruby/bin:$PATH"
# ^ All lines above are PREFIXED to the default PATH, with lower lines being earlier in the final PATH.
# ---- default PATH divider ----
# v All lines below are SUFFIXED to the default PATH, with lower lines being later in the final PATH.
export PATH="$PATH:$ANDROID_HOME/tools:$ANDROID_HOME/platform-tools"
export PATH="$PATH:/Applications/Visual Studio Code.app/Contents/Resources/app/bin"
