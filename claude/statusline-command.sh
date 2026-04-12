#!/usr/bin/env bash
# Claude Code status line

input=$(cat)

IFS=$'\t' read -r cwd model ctx_pct ctx_size ctx_input ctx_cache_create ctx_cache_read \
    five_h_pct seven_d_pct five_h_reset seven_d_reset < <(
    echo "$input" | jq -r '[
        (.cwd // ""),
        (.model.display_name // "-"),
        (.context_window.used_percentage // 0 | floor),
        (.context_window.context_window_size // 200000),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.cache_creation_input_tokens // 0),
        (.context_window.current_usage.cache_read_input_tokens // 0),
        (.rate_limits.five_hour.used_percentage // 0 | floor),
        (.rate_limits.seven_day.used_percentage // 0 | floor),
        (.rate_limits.five_hour.resets_at // 0),
        (.rate_limits.seven_day.resets_at // 0)
    ] | @tsv'
)

# ANSI color codes
BOLD=$(printf '\033[1m')
RESET=$(printf '\033[0m')
DIM=$(printf '\033[2m')
COLOR_DIR=$(printf '\033[1;34m')      # bold ANSI blue   (headline PATH)
COLOR_GIT=$(printf '\033[1;36m')      # bold ANSI cyan   (headline BRANCH)
COLOR_STATUS=$(printf '\033[1;35m')   # bold magenta     (headline STATUS)
COLOR_CLAUDE=$(printf '\033[38;5;173m') # terracotta orange (Claude brand)
COLOR_KEY=$(printf '\033[38;5;174m')   # section keys (close to Claude brand)
COLOR_LABEL=$(printf '\033[38;5;245m')
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
    tracking="${git_status_raw%%$'\n'*}"
    if [[ "$tracking" =~ ahead\ ([0-9]+) ]]; then
        ahead="${BASH_REMATCH[1]}"
    fi
    if [[ "$tracking" =~ behind\ ([0-9]+) ]]; then
        behind="${BASH_REMATCH[1]}"
    fi

    # Parse status lines - priority order matches headline's headline-git-status-counts()
    staged=0; changed=0; untracked=0; conflicts=0
    while IFS= read -r line; do
        xy="${line:0:2}"
        case "$xy" in
            '##') continue ;;
            '??') untracked=$((untracked + 1)) ;;
            *)
                if [[ "$xy" =~ ^(U[ADU]|[AD]U|AA|DD) ]]; then
                    conflicts=$((conflicts + 1))
                elif [[ "$xy" =~ ^[MTADRC]\  ]]; then
                    staged=$((staged + 1))
                elif [[ "$xy" =~ ^[MTARC][MTD] ]]; then
                    staged=$((staged + 1)); changed=$((changed + 1))
                elif [[ "$xy" =~ ^\ [MTADRC] ]]; then
                    changed=$((changed + 1))
                fi
                ;;
        esac
    done <<< "$git_status_raw"

    # Stash count
    stashed=0
    if git -C "$cwd" rev-parse --verify refs/stash >/dev/null 2>&1; then
        stashed=$(git -C "$cwd" rev-list --walk-reflogs --count refs/stash 2>/dev/null)
        stashed=${stashed:-0}
    fi

    # Build status string - HL_GIT_STATUS_ORDER: STAGED CHANGED UNTRACKED BEHIND AHEAD STASHED CONFLICTS
    # format is count+symbol (e.g. 3!)
    entries=("${staged}:+" "${changed}:!" "${untracked}:?" "${behind}:↓" "${ahead}:↑" "${stashed}:*" "${conflicts}:✘")
    git_status_str=""
    for entry in "${entries[@]}"; do
        count="${entry%%:*}"
        symbol="${entry#*:}"
        if [ "$count" -gt 0 ]; then
            [ -n "$git_status_str" ] && git_status_str="${git_status_str}${DIM}${COLOR_LABEL}|${RESET}${COLOR_STATUS}"
            git_status_str="${git_status_str}${count}${symbol}"
        fi
    done

    # Assemble branch + optional status brackets
    if [ -n "$git_status_str" ]; then
        status_brackets="${DIM}${COLOR_LABEL} [${RESET}${COLOR_STATUS}${git_status_str}${DIM}${COLOR_LABEL}]${RESET}"
    else
        status_brackets=""
    fi
    git_part="${DIM}${COLOR_LABEL} | ${RESET}${BOLD}${COLOR_GIT}${branch}${RESET}${status_brackets}"
fi

# --- Context usage ---
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

# Convert ASCII digits to superscript equivalents
to_super() {
    local s="$1"
    s="${s//0/⁰}"; s="${s//1/¹}"; s="${s//2/²}"; s="${s//3/³}"; s="${s//4/⁴}"
    s="${s//5/⁵}"; s="${s//6/⁶}"; s="${s//7/⁷}"; s="${s//8/⁸}"; s="${s//9/⁹}"
    printf '%s' "$s"
}

# Helper: 10-char wide bar.
# Optional second arg: time_pct (0-100) marks current position in the time window;
# -1 (default) means no marker. Cells after the marker get strikethrough.
make_bar() {
    local pct=$1
    local time_pct=${2:--1}
    local WIDTH=10
    local label
    label="$(to_super "$(printf '%02d' "$pct")")"
    local label_len=${#label}
    local filled=$(( pct * WIDTH / 100 ))

    # Compute marker cell index (-1 = none)
    local marker_pos=-1
    if [ "$time_pct" -ge 0 ] 2>/dev/null; then
        marker_pos=$(( time_pct * WIDTH / 100 ))
        [ "$marker_pos" -ge "$WIDTH" ] && marker_pos=$(( WIDTH - 1 ))
    fi

    local FILL_IDX
    if   [ "$pct" -ge 90 ]; then FILL_IDX=203
    elif [ "$pct" -ge 70 ]; then FILL_IDX=220
    else                          FILL_IDX=110
    fi
    local EMPTY_IDX=236

    local BG_FILL=$(printf '\033[48;5;%sm' "$FILL_IDX")
    local BG_EMPTY=$(printf '\033[48;5;%sm' "$EMPTY_IDX")
    local FG_FILL=$(printf '\033[1;38;5;236m')  # bold dark charcoal on fill
    local FG_EMPTY=$(printf '\033[1;38;5;245m') # bold medium gray on empty
    local ST=$(printf '\033[9m')
    local NO_ST=$(printf '\033[29m')

    local pad_r=$(( WIDTH - label_len ))
    local content
    printf -v content "%s%${pad_r}s" "$label" ""

    local bar="" i st
    for ((i=0; i<WIDTH; i++)); do
        # Strikethrough all cells after the marker position (remaining time)
        if [ "$marker_pos" -ge 0 ] && [ "$i" -gt "$marker_pos" ]; then
            st="$ST"
        else
            st="$NO_ST"
        fi
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}${BG_FILL}${FG_FILL}${st}${content:$i:1}"
        else
            bar="${bar}${BG_EMPTY}${FG_EMPTY}${st}${content:$i:1}"
        fi
    done
    printf '%s%s' "$bar" "$RESET"
}

ctx_bar=$(make_bar "$ctx_pct")

# --- Claude.ai rate limits ---
now=$(date +%s)

# Format seconds remaining as "Xd Yh", "Xh", or "Xm"
format_remaining() {
    [ -z "$1" ] || [ "$1" -eq 0 ] 2>/dev/null && echo "-" && return
    local remaining=$(( $1 - now ))
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

# How far through each window are we right now?
# Returns 0-100 (percent elapsed), or -1 if no reset timestamp available.
compute_time_pct() {
    local reset_at=$1 window_secs=$2
    [ -z "$reset_at" ] || [ "$reset_at" -eq 0 ] 2>/dev/null && echo -1 && return
    local elapsed=$(( window_secs - (reset_at - now) ))
    [ "$elapsed" -le 0 ] && echo 0 && return
    [ "$elapsed" -ge "$window_secs" ] && echo 100 && return
    echo $(( elapsed * 100 / window_secs ))
}

five_h_time_pct=$(compute_time_pct "$five_h_reset" 18000)
seven_d_time_pct=$(compute_time_pct "$seven_d_reset" 604800)

five_h_bar=$(make_bar "$five_h_pct" "$five_h_time_pct")
seven_d_bar=$(make_bar "$seven_d_pct" "$seven_d_time_pct")
five_h_remaining=$(format_remaining "$five_h_reset")
seven_d_remaining=$(format_remaining "$seven_d_reset")

five_h_part=" ${SEP} ${DIM}${COLOR_KEY}5h${RESET} ${five_h_bar} ${DIM}󰔛 ${five_h_remaining}${RESET}"
seven_d_part=" ${SEP} ${DIM}${COLOR_KEY}7d${RESET} ${seven_d_bar} ${DIM}󰔛 ${seven_d_remaining}${RESET}"

# --- Output ---
printf '%s%s%s%s%s\n' \
    "$BOLD" "$COLOR_DIR" "$dir_display" "$RESET" "$git_part"
printf '%s%s%s %s %s %s%s%s\n' \
    "$BOLD" "$COLOR_CLAUDE" "$model" \
    "$SEP" \
    "${DIM}${COLOR_KEY}${RESET} ${ctx_bar}" \
    "${DIM}${ctx_used_fmt}/${ctx_size_fmt}${RESET}" \
    "$five_h_part" \
    "$seven_d_part"
