# Xterm color chart: https://upload.wikimedia.org/wikipedia/commons/1/15/Xterm_256color_chart.svg

local new_line=$'\n'
local bold_start="%B"
local bold_end="%b"
local reset_color="%{$reset_color%}"

local current_dir_output="$bold_start$FG[012]%~$reset_color$bold_end"

# Function to tell if it is a git repo or not.
# This is so I can add an indicator that is not an immediate prefix or a suffix to the ZSH_GIT... vars.
function separated_git_indicator() {
    if git rev-parse --is-inside-work-tree &>/dev/null; then
        printf " %s⊢%s " \
            "$bold_start" \
            "$bold_end"
    else
        printf ""
    fi
}

PROMPT="$new_line$current_dir_output"
# When calling functions, either use single-quotes, or double-quotes with an escaped \$ sign before the function.
PROMPT+="\$(separated_git_indicator)"
# Related: 'git_prompt_info' function only works when it's directly in the PROMPT, not if nested in another function.
# This seems to be a limitation of how omz themes work.
PROMPT+="\$(git_remote_status)\$(git_prompt_info)"
PROMPT+="$new_line$bold_start$FG[005]❯ $reset_color$bold_end"

RPROMPT=""

# Zsh theme vars.
ZSH_THEME_GIT_PROMPT_PREFIX="$bold_start$FG[011]"
ZSH_THEME_GIT_PROMPT_SUFFIX="$reset_color$bold_end"
ZSH_THEME_GIT_PROMPT_DIRTY="$FG[172] •$reset_color"
ZSH_THEME_GIT_PROMPT_BEHIND_REMOTE="$bold_start$FG[013]⏷$reset_color$bold_end "
ZSH_THEME_GIT_PROMPT_AHEAD_REMOTE="$bold_start$FG[113]⏶$reset_color$bold_end "
ZSH_THEME_GIT_PROMPT_DIVERGED_REMOTE="$bold_start$FG[013]⏷$FG[113]⏶$reset_color$bold_end "
