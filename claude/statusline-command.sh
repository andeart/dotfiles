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
COLOR_GREEN=$(printf '\033[38;5;113m')
COLOR_YELLOW=$(printf '\033[38;5;220m')
COLOR_RED=$(printf '\033[38;5;203m')
COLOR_CYAN=$(printf '\033[38;5;117m')
COLOR_MAGENTA=$(printf '\033[38;5;183m')
COLOR_LABEL=$(printf '\033[38;5;245m')
COLOR_DUR=$(printf '\033[38;5;215m')  # soft orange for durations
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

# Helper: format milliseconds as Xm YYs or Xh Ym YYs
format_duration() {
    local ms=$1
    local total_secs=$((ms / 1000))
    local hours=$((total_secs / 3600))
    local mins=$(( (total_secs % 3600) / 60 ))
    local secs=$((total_secs % 60))
    if [ "$hours" -gt 0 ]; then
        printf '%dh %dm %02ds' "$hours" "$mins" "$secs"
    else
        printf '%dm %02ds' "$mins" "$secs"
    fi
}

# --- Timing ---
api_dur_ms=$(echo "$input" | jq -r '.cost.total_api_duration_ms // 0')
total_dur_ms=$(echo "$input" | jq -r '.cost.total_duration_ms // 0')
timing_part=""
if [ "$total_dur_ms" -gt 0 ]; then
    api_fmt=$(format_duration "$api_dur_ms")
    total_fmt=$(format_duration "$total_dur_ms")
    timing_part=" ${SEP} ${BOLD}${COLOR_DUR}⏱ ${api_fmt}${RESET} ${FAINT}${COLOR_LABEL}/${RESET} ${BOLD}${COLOR_DUR}${total_fmt}${RESET}"
fi

# --- Output ---
printf '%s%s%s%s%s\n' \
    "$BOLD" "$COLOR_DIR" "$dir_display" "$RESET" "$git_part"
printf '%s %s%s%s %s %s %s%s %s%s\n' \
    "$SEP" \
    "$BOLD" "$COLOR_MAGENTA" "$model" \
    "$SEP" \
    "${BOLD}Context ${ctx_bar}" \
    "${BOLD}${COLOR_CYAN}" "${ctx_pct}%${RESET}" \
    "${BOLD}${DIM}(${ctx_used_fmt}/${ctx_size_fmt})${RESET}" \
    "$timing_part"
