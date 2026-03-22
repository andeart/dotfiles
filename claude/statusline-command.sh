#!/bin/bash
# Claude Code status line

input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd')

# ANSI color codes
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')
DIM=$(printf '\033[2m')
FAINT=$(printf '\033[2m')
COLOR_DIR=$(printf '\033[1;34m')      # bold ANSI blue   (headline PATH)
COLOR_GIT=$(printf '\033[1;36m')      # bold ANSI cyan   (headline BRANCH)
COLOR_STATUS=$(printf '\033[1;35m')   # bold magenta     (headline STATUS)
COLOR_GREEN=$(printf '\033[38;5;109m') # cool slate
COLOR_YELLOW=$(printf '\033[38;5;220m')
COLOR_RED=$(printf '\033[38;5;203m')
COLOR_CYAN=$(printf '\033[38;5;117m')
COLOR_CLAUDE=$(printf '\033[38;5;173m') # terracotta orange (Claude brand)
COLOR_KEY=$(printf '\033[38;5;174m')   # section keys (close to Claude brand)
# COLOR_GOLD=$(printf '\033[38;5;179m')  # muted gold (was used for percentages, now inside bars)
COLOR_LABEL=$(printf '\033[38;5;245m')
# COLOR_DUR=$(printf '\033[38;5;215m')  # soft orange for durations (used by timing)
SEP="${COLOR_LABEL}│${RESET}"

# --- Directory + Git ---
dir_display=$(echo "$cwd" | sed "s|^$HOME|~|")

git_part=""
if git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    # Branch name; detached HEAD gets :hash prefix (matches headline-git-branch)
    branch=$(git -C "$cwd" symbolic-ref --quiet --short HEAD 2>/dev/null)
    if [ -z "$branch" ]; then
        short_hash=$(git -C "$cwd" rev-parse --short HEAD 2>/dev/null)
        branch=":${short_hash}"
    fi

    # Single git status call covers tracking line + file status
    git_status_raw=$(git -C "$cwd" status --porcelain -b 2>/dev/null)

    # Parse tracking line for ahead/behind counts
    ahead=0; behind=0
    tracking=$(printf '%s\n' "$git_status_raw" | head -1)
    if printf '%s\n' "$tracking" | grep -q 'ahead'; then
        ahead=$(printf '%s\n' "$tracking" | grep -o 'ahead [0-9]*' | grep -o '[0-9]*')
        ahead=${ahead:-0}
    fi
    if printf '%s\n' "$tracking" | grep -q 'behind'; then
        behind=$(printf '%s\n' "$tracking" | grep -o 'behind [0-9]*' | grep -o '[0-9]*')
        behind=${behind:-0}
    fi

    # Parse status lines — priority order matches headline's headline-git-status-counts()
    staged=0; changed=0; untracked=0; conflicts=0
    while IFS= read -r line; do
        xy="${line:0:2}"
        case "$xy" in
            '##'|'!!') continue ;;
        esac
        if printf '%s\n' "$xy" | grep -qE '^(U[ADU]|[AD]U|AA|DD)'; then
            conflicts=$((conflicts + 1))
        elif [ "$xy" = '??' ]; then
            untracked=$((untracked + 1))
        elif printf '%s\n' "$xy" | grep -qE '^[MTADRC] '; then
            staged=$((staged + 1))
        elif printf '%s\n' "$xy" | grep -qE '^[MTARC][MTD]'; then
            staged=$((staged + 1)); changed=$((changed + 1))
        elif printf '%s\n' "$xy" | grep -qE '^ [MTADRC]'; then
            changed=$((changed + 1))
        fi
    done <<< "$git_status_raw"

    # Stash count
    stashed=0
    if git -C "$cwd" rev-parse --verify refs/stash >/dev/null 2>&1; then
        stashed=$(git -C "$cwd" rev-list --walk-reflogs --count refs/stash 2>/dev/null)
        stashed=${stashed:-0}
    fi

    # Build status string — HL_GIT_STATUS_ORDER: STAGED CHANGED UNTRACKED BEHIND AHEAD
    # DIVERGED(always 0) STASHED CONFLICTS; format is count+symbol (e.g. 3!)
    entries=("${staged}:+" "${changed}:!" "${untracked}:?" "${behind}:↓" "${ahead}:↑" "0:↕" "${stashed}:*" "${conflicts}:✘")
    git_status_str=""
    for entry in "${entries[@]}"; do
        count="${entry%%:*}"
        symbol="${entry#*:}"
        if [ "$count" -gt 0 ]; then
            [ -n "$git_status_str" ] && git_status_str="${git_status_str}${FAINT}${COLOR_LABEL}|${RESET}${COLOR_STATUS}"
            git_status_str="${git_status_str}${count}${symbol}"
        fi
    done

    # Assemble branch + optional status brackets
    if [ -n "$git_status_str" ]; then
        status_brackets="${FAINT}${COLOR_LABEL} [${RESET}${COLOR_STATUS}${git_status_str}${FAINT}${COLOR_LABEL}]${RESET}"
    else
        status_brackets=""
    fi
    git_part="${FAINT}${COLOR_LABEL} | ${RESET}${BOLD}${COLOR_GIT}${branch}${RESET}${status_brackets}"
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

# Helper: 10-char wide bar with rounded caps (Nerd Font U+E0B6/U+E0B4)
# Caps use bar bg color as fg against terminal default, creating a pill effect
make_bar() {
    local pct=$1
    local WIDTH=10
    local label="${pct}%"
    local label_len=${#label}
    local filled=$(( pct * WIDTH / 100 ))

    local FILL_IDX FILL_IDX
    if   [ "$pct" -ge 90 ]; then FILL_IDX=203
    elif [ "$pct" -ge 70 ]; then FILL_IDX=220
    else                          FILL_IDX=110
    fi
    local EMPTY_IDX=236

    local BG_FILL=$(printf '\033[48;5;%sm' "$FILL_IDX")
    local BG_EMPTY=$(printf '\033[48;5;%sm' "$EMPTY_IDX")
    local FG_FILL=$(printf '\033[1;38;5;236m')  # bold dark charcoal on fill
    local FG_EMPTY=$(printf '\033[1;38;5;245m') # bold medium gray on empty


    local pad_r=$(( WIDTH - label_len - 1 ))
    local content
    printf -v content " %s%${pad_r}s" "$label" ""

    local bar="" i
    for ((i=0; i<WIDTH; i++)); do
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}${BG_FILL}${FG_FILL}${content:$i:1}"
        else
            bar="${bar}${BG_EMPTY}${FG_EMPTY}${content:$i:1}"
        fi
    done
    printf '%s%s' "$bar" "$RESET"
}

ctx_bar=$(make_bar "$ctx_pct")

# --- Claude.ai rate limits ---
# Format seconds remaining as "Xd Yh", "Xh", or "Xm"
format_remaining() {
    local remaining=$(( $1 - $(date +%s) ))
    [ "$remaining" -le 0 ] && echo "now" && return
    local days=$(( remaining / 86400 ))
    local hours=$(( (remaining % 86400) / 3600 ))
    local mins=$(( (remaining % 3600) / 60 ))
    if [ "$days" -gt 0 ]; then
        echo "${days}d ${hours}h"
    elif [ "$hours" -gt 0 ]; then
        echo "${hours}h"
    else
        echo "${mins}m"
    fi
}

five_h_pct=$(echo "$input" | jq -r '.rate_limits.five_hour.used_percentage // 0' | cut -d. -f1)
seven_d_pct=$(echo "$input" | jq -r '.rate_limits.seven_day.used_percentage // 0' | cut -d. -f1)
five_h_reset=$(echo "$input" | jq -r '.rate_limits.five_hour.resets_at // 0')
seven_d_reset=$(echo "$input" | jq -r '.rate_limits.seven_day.resets_at // 0')
five_h_pct=${five_h_pct:-0}
seven_d_pct=${seven_d_pct:-0}
five_h_reset=${five_h_reset:-0}
seven_d_reset=${seven_d_reset:-0}

five_h_bar=$(make_bar "$five_h_pct")
seven_d_bar=$(make_bar "$seven_d_pct")
five_h_remaining=$(format_remaining "$five_h_reset")
seven_d_remaining=$(format_remaining "$seven_d_reset")

five_h_part=" ${SEP} ${DIM}${COLOR_KEY}5h${RESET} ${five_h_bar} ${DIM}󰔛 ${five_h_remaining}${RESET}"
seven_d_part=" ${SEP} ${DIM}${COLOR_KEY}7d${RESET} ${seven_d_bar} ${DIM}󰔛 ${seven_d_remaining}${RESET}"

# # Helper: format milliseconds as Xm YYs or Xh Ym YYs
# format_duration() {
#     local ms=$1
#     local total_secs=$((ms / 1000))
#     local hours=$((total_secs / 3600))
#     local mins=$(( (total_secs % 3600) / 60 ))
#     local secs=$((total_secs % 60))
#     if [ "$hours" -gt 0 ]; then
#         printf '%dh %dm %02ds' "$hours" "$mins" "$secs"
#     else
#         printf '%dm %02ds' "$mins" "$secs"
#     fi
# }
#
# # --- Timing ---
# api_dur_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
# total_dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
# timing_part=""
# if [ "$total_dur_ms" -gt 0 ]; then
#     api_fmt=$(format_duration "$api_dur_ms")
#     total_fmt=$(format_duration "$total_dur_ms")
#     timing_part=" ${SEP} ${BOLD}${COLOR_DUR}⏱ ${api_fmt}${RESET} ${FAINT}${COLOR_LABEL}/${RESET} ${BOLD}${COLOR_DUR}${total_fmt}${RESET}"
# fi

# --- Output ---
printf '%s%s%s%s%s\n' \
    "$BOLD" "$COLOR_DIR" "$dir_display" "$RESET" "$git_part"
printf '%s%s%s %s %s %s%s%s\n' \
    "$BOLD" "$COLOR_CLAUDE" "$model" \
    "$SEP" \
    "${DIM}${COLOR_KEY}${RESET} ${ctx_bar}" \
    "${BOLD}${DIM}${ctx_used_fmt}/${ctx_size_fmt}${RESET}" \
    "$five_h_part" \
    "$seven_d_part"
    # "$timing_part"
