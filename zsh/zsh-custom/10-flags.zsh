export LDFLAGS="-L/${BREW_PREFIX}/opt/ruby/lib"
export CPPFLAGS="-I/${BREW_PREFIX}/opt/ruby/include"

# Export $ZSH_CUSTOM explicitly for access in bash scripts.
export ZSH_CUSTOM="$ZSH_CUSTOM"

# Avoid opening sub-editors (default oh-my-zsh behavior) for certain commands.
export PAGER='less'
export LESS='-R'
export GIT_PAGER=""

export EDITOR="code --wait"
export VISUAL="code --wait"
export GIT_EDITOR="code --wait"
