#!/bin/bash
# Claude Code status line

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# ANSI color codes
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')
DIM=$(printf '\033[2m')
COLOR_DIR=$(printf '\033[38;5;12m')
COLOR_GIT=$(printf '\033[38;5;11m')
COLOR_DIRTY=$(printf '\033[38;5;172m')
COLOR_AHEAD=$(printf '\033[38;5;113m')
COLOR_BEHIND=$(printf '\033[38;5;13m')
COLOR_GREEN=$(printf '\033[38;5;113m')
COLOR_YELLOW=$(printf '\033[38;5;220m')
COLOR_RED=$(printf '\033[38;5;203m')
COLOR_CYAN=$(printf '\033[38;5;117m')
COLOR_MAGENTA=$(printf '\033[38;5;183m')
COLOR_LABEL=$(printf '\033[38;5;245m')
SEP="${COLOR_LABEL}│${RESET}"

# --- Directory + Git ---
dir_display=$(echo "$cwd" | sed "s|^$HOME|~|")

git_part=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
    dirty=""
    if [ -n "$(git -C "$cwd" status --porcelain 2>/dev/null)" ]; then
        dirty="${COLOR_DIRTY} •${RESET}${BOLD}${COLOR_GIT}"
    fi

    ahead_behind=$(git -C "$cwd" rev-list --left-right --count HEAD...@{upstream} 2>/dev/null)
    remote_status=""
    if [ -n "$ahead_behind" ]; then
        ahead=$(echo "$ahead_behind" | awk '{print $1}')
        behind=$(echo "$ahead_behind" | awk '{print $2}')
        if [ "$ahead" -gt 0 ] && [ "$behind" -gt 0 ]; then
            remote_status="${COLOR_BEHIND}${BOLD}⏷${COLOR_AHEAD}⏶${RESET}${BOLD}${COLOR_GIT} "
        elif [ "$ahead" -gt 0 ]; then
            remote_status="${COLOR_AHEAD}${BOLD}⏶${RESET}${BOLD}${COLOR_GIT} "
        elif [ "$behind" -gt 0 ]; then
            remote_status="${COLOR_BEHIND}${BOLD}⏷${RESET}${BOLD}${COLOR_GIT} "
        fi
    fi

    git_part=" ${BOLD}⊢${RESET} ${remote_status}${BOLD}${COLOR_GIT}${branch}${dirty}${RESET}"
fi

# --- Model ---
model=$(echo "$input" | jq -r '.model.display_name // "—"')

# --- Context usage ---
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
ctx_size=$(echo "$input" | jq -r '.context_window.context_window_size // 200000')
ctx_input=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // 0')
ctx_cache_create=$(echo "$input" | jq -r '.context_window.current_usage.cache_creation_input_tokens // 0')
ctx_cache_read=$(echo "$input" | jq -r '.context_window.current_usage.cache_read_input_tokens // 0')
ctx_used=$((ctx_input + ctx_cache_create + ctx_cache_read))

if [ "$ctx_used" -ge 1000 ]; then
    ctx_used_fmt="$((ctx_used / 1000))k"
else
    ctx_used_fmt="$ctx_used"
fi
if [ "$ctx_size" -ge 1000 ]; then
    ctx_size_fmt="$((ctx_size / 1000))k"
else
    ctx_size_fmt="$ctx_size"
fi

# Helper: build a color-coded bar
make_bar() {
    local pct=$1 width=$2 bar_color
    local filled=$((pct * width / 100))
    local empty=$((width - filled))
    if [ "$pct" -ge 90 ]; then
        bar_color="$COLOR_RED"
    elif [ "$pct" -ge 70 ]; then
        bar_color="$COLOR_YELLOW"
    else
        bar_color="$COLOR_GREEN"
    fi
    local f=$(printf "%${filled}s" | tr ' ' '◼')
    local e=$(printf "%${empty}s" | tr ' ' '◻')
    printf '%s%s%s%s%s' "$bar_color" "$f" "$DIM" "$e" "$RESET"
}

ctx_bar=$(make_bar "$ctx_pct" 10)

# --- Output ---
printf '%s%s%s%s%s %s %s%s%s %s %s %s%s %s\n' \
    "$BOLD" "$COLOR_DIR" "$dir_display" "$RESET" "$git_part" \
    "$SEP" \
    "$BOLD" "$COLOR_MAGENTA" "$model" \
    "$SEP" \
    "${BOLD}Context ${ctx_bar}" \
    "${BOLD}${COLOR_CYAN}" "${ctx_pct}%${RESET}" \
    "${BOLD}${DIM}(${ctx_used_fmt}/${ctx_size_fmt})${RESET}"
