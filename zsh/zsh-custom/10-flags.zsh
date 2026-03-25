export LDFLAGS="-L${BREW_PREFIX}/opt/ruby/lib"
export CPPFLAGS="-I${BREW_PREFIX}/opt/ruby/include"

# Avoid opening sub-editors (default oh-my-zsh behavior) for certain commands.
export PAGER='less'
export LESS='-R'
export GIT_PAGER=""
