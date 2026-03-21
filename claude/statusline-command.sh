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
COLOR_GOLD=$(printf '\033[38;5;179m')  # muted gold for percentages
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

# Segmented bar characters (Nerd Font) — empty and full variants for left/middle/right positions
_BEL=$(printf '\xee\xb8\x80') _BEM=$(printf '\xee\xb8\x81') _BER=$(printf '\xee\xb8\x82')  # empty: left, middle, right
_BFL=$(printf '\xee\xb8\x83') _BFM=$(printf '\xee\xb8\x84') _BFR=$(printf '\xee\xb8\x85')  # full:  left, middle, right

# Helper: build a 5-slot segmented bar (no loops — case on 6 possible fill counts)
# Each slot = 20%; slot is full if pct >= slot_start + 10, i.e. full_count = (pct+10)/20
make_bar() {
    local pct=$1 bar_color
    local full=$(( (pct + 10) / 20 ))
    [ "$full" -gt 5 ] && full=5

    if   [ "$pct" -ge 90 ]; then bar_color="$COLOR_RED"
    elif [ "$pct" -ge 70 ]; then bar_color="$COLOR_YELLOW"
    else                          bar_color="$COLOR_GREEN"
    fi

    case "$full" in
        0) printf '%s%s%s'     "$DIM"       "$_BEL$_BEM$_BEM$_BEM$_BER"                   "$RESET" ;;
        1) printf '%s%s%s%s%s' "$bar_color" "$_BFL"          "$DIM" "$_BEM$_BEM$_BEM$_BER" "$RESET" ;;
        2) printf '%s%s%s%s%s' "$bar_color" "$_BFL$_BFM"     "$DIM" "$_BEM$_BEM$_BER"      "$RESET" ;;
        3) printf '%s%s%s%s%s' "$bar_color" "$_BFL$_BFM$_BFM"     "$DIM" "$_BEM$_BER"      "$RESET" ;;
        4) printf '%s%s%s%s%s' "$bar_color" "$_BFL$_BFM$_BFM$_BFM"     "$DIM" "$_BER"      "$RESET" ;;
        5) printf '%s%s%s'     "$bar_color" "$_BFL$_BFM$_BFM$_BFM$_BFR"                    "$RESET" ;;
    esac
}

ctx_bar=$(make_bar "$ctx_pct")

# --- Claude.ai usage (cached, TTL 5 min) ---
USAGE_CACHE="${HOME}/.claude/usage_cache"
five_h_pct=0
seven_d_pct=0

# Parse an ISO 8601 UTC timestamp (e.g. "2026-03-21T06:00:00.247097+00:00") to epoch
parse_reset_epoch() {
    local ts="$1"
    local clean
    clean=$(echo "$ts" | sed 's/\.[0-9]*//' | sed 's/[+-][0-9][0-9]:[0-9][0-9]$//')
    TZ=UTC date -j -f "%Y-%m-%dT%H:%M:%S" "$clean" +%s 2>/dev/null || echo 0
}

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

fetch_usage() {
    local now
    now=$(date +%s)
    if [ -f "$USAGE_CACHE" ]; then
        local cache_time
        cache_time=$(head -1 "$USAGE_CACHE" 2>/dev/null)
        if [ -n "$cache_time" ] && [ $((now - cache_time)) -lt 300 ]; then
            tail -1 "$USAGE_CACHE"
            return
        fi
    fi

    local token
    token=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null \
        | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null)
    [ -z "$token" ] && echo "0 0 0 0" && return

    local response
    response=$(curl -s --max-time 5 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "anthropic-beta: oauth-2025-04-20" 2>/dev/null)

    local fh sd fh_reset sd_reset
    fh=$(echo "$response" | jq -r '.five_hour.utilization // 0' 2>/dev/null | cut -d. -f1)
    sd=$(echo "$response" | jq -r '.seven_day.utilization // 0' 2>/dev/null | cut -d. -f1)
    fh_reset=$(parse_reset_epoch "$(echo "$response" | jq -r '.five_hour.resets_at // empty')")
    sd_reset=$(parse_reset_epoch "$(echo "$response" | jq -r '.seven_day.resets_at // empty')")
    fh=${fh:-0}; sd=${sd:-0}; fh_reset=${fh_reset:-0}; sd_reset=${sd_reset:-0}

    printf '%s\n%s %s %s %s\n' "$now" "$fh" "$sd" "$fh_reset" "$sd_reset" > "$USAGE_CACHE"
    echo "$fh $sd $fh_reset $sd_reset"
}

read -r five_h_pct seven_d_pct five_h_reset seven_d_reset <<< "$(fetch_usage)"
five_h_pct=${five_h_pct:-0}
seven_d_pct=${seven_d_pct:-0}
five_h_reset=${five_h_reset:-0}
seven_d_reset=${seven_d_reset:-0}

five_h_bar=$(make_bar "$five_h_pct")
seven_d_bar=$(make_bar "$seven_d_pct")
five_h_remaining=$(format_remaining "$five_h_reset")
seven_d_remaining=$(format_remaining "$seven_d_reset")

five_h_part=" ${SEP} ${DIM}${COLOR_KEY}5h${RESET} ${five_h_bar} ${BOLD}${COLOR_GOLD}${five_h_pct}%${RESET} ${DIM}󰔛 ${five_h_remaining}${RESET}"
seven_d_part=" ${SEP} ${DIM}${COLOR_KEY}7d${RESET} ${seven_d_bar} ${BOLD}${COLOR_GOLD}${seven_d_pct}%${RESET} ${DIM}󰔛 ${seven_d_remaining}${RESET}"

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
printf '%s%s%s %s %s %s%s %s%s%s\n' \
    "$BOLD" "$COLOR_CLAUDE" "$model" \
    "$SEP" \
    "${DIM}${COLOR_KEY}${RESET} ${ctx_bar}" \
    "${BOLD}${COLOR_GOLD}" "${ctx_pct}%${RESET}" \
    "${BOLD}${DIM}${ctx_used_fmt}/${ctx_size_fmt}${RESET}" \
    "$five_h_part" \
    "$seven_d_part"
    # "$timing_part"
