#!/usr/bin/env bash
# Claude Code status line

input=$(</dev/stdin)

IFS=$'\t' read -r model ctx_pct ctx_input ctx_cache_create ctx_cache_read \
    five_h_pct seven_d_pct five_h_reset seven_d_reset effort < <(
    jq -r '[
        (.model.display_name // "-"),
        (.context_window.used_percentage // 0 | floor),
        (.context_window.current_usage.input_tokens // 0),
        (.context_window.current_usage.cache_creation_input_tokens // 0),
        (.context_window.current_usage.cache_read_input_tokens // 0),
        (.rate_limits.five_hour.used_percentage // 0 | floor),
        (.rate_limits.seven_day.used_percentage // 0 | floor),
        (.rate_limits.five_hour.resets_at // 0),
        (.rate_limits.seven_day.resets_at // 0),
        (.effort.level // "")
    ] | @tsv' <<<"$input"
)

# Defensive defaults so numeric tests don't error if jq ever fails entirely
: "${ctx_pct:=0}" "${ctx_input:=0}" "${ctx_cache_create:=0}" "${ctx_cache_read:=0}"
: "${five_h_pct:=0}" "${seven_d_pct:=0}" "${five_h_reset:=0}" "${seven_d_reset:=0}"

# "-" means the key was absent or null.
ws_dir=$(jq -r '.workspace.current_dir // "-"' <<<"$input")

# Long-context models arrive as e.g. "Opus 4.8 (1M context)". Reduce the
# parenthetical to a bare size suffix: "Opus 4.8 1M". Matched as a whole so any
# other parenthetical is left intact.
if [[ $model =~ ^(.*)\ \((.*)\ context\)$ ]]; then
    model="${BASH_REMATCH[1]} ${BASH_REMATCH[2]}"
fi

# ANSI color codes
BOLD=$'\033[1m'
RESET=$'\033[0m'
DIM=$'\033[2m'
COLOR_CLAUDE=$'\033[38;5;173m' # terracotta orange (Claude brand)
COLOR_KEY=$'\033[38;5;174m'    # section keys (close to Claude brand)
COLOR_LABEL=$'\033[38;5;245m'
SEP="${COLOR_LABEL}│${RESET}"

# Bar rendering constants
BAR_FG_FILL=$'\033[1;38;5;236m'  # bold dark charcoal on fill
BAR_FG_EMPTY=$'\033[1;38;5;245m' # bold medium gray on empty
BAR_BG_EMPTY=$'\033[48;5;236m'
BAR_ST=$'\033[9m'
BAR_NO_ST=$'\033[29m'

# --- Context usage ---
ctx_used=$((ctx_input + ctx_cache_create + ctx_cache_read))

# Convert ASCII digits to superscript equivalents, plus "k" to U+1D37.
# JetBrains Mono lacks U+1D37, but many monospace system fonts carry it, so
# terminal font fallback covers it. Subscript k (U+2096) is not a viable swap:
# only the proportional system font has it, which the terminal grid won't use.
to_super() {
    local s="$1"
    s="${s//0/⁰}"; s="${s//1/¹}"; s="${s//2/²}"; s="${s//3/³}"; s="${s//4/⁴}"
    s="${s//5/⁵}"; s="${s//6/⁶}"; s="${s//7/⁷}"; s="${s//8/⁸}"; s="${s//9/⁹}"
    s="${s//k/ᴷ}"
    printf '%s' "$s"
}

# Helper: 10-char wide bar, filled in proportion to pct, with a superscript
# label riding along the top.
# Optional second arg: time_pct (0-100) marks current position in the time window;
# -1 (default) means no marker. Cells after the marker get strikethrough.
# Optional third arg: ASCII text for the label, overriding the default of pct
# itself. Lets the fill and the label report different quantities.
make_bar() {
    local pct=$1
    local time_pct=${2:--1}
    local WIDTH=10
    local label_raw=${3:-}
    [ -z "$label_raw" ] && printf -v label_raw '%02d' "$pct"
    local label
    label="$(to_super "$label_raw")"
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

    local BG_FILL
    printf -v BG_FILL '\033[48;5;%sm' "$FILL_IDX"

    # Clamped at 0 so a label wider than the bar degrades to truncation in the
    # render loop rather than a printf error here.
    local pad=$(( WIDTH - ${#label} ))
    [ "$pad" -lt 0 ] && pad=0
    local content
    printf -v content "%s%${pad}s" "$label" ""

    local bar="" i st
    for ((i=0; i<WIDTH; i++)); do
        # Strikethrough all cells after the marker position (remaining time)
        if [ "$marker_pos" -ge 0 ] && [ "$i" -gt "$marker_pos" ]; then
            st="$BAR_ST"
        else
            st="$BAR_NO_ST"
        fi
        if [ "$i" -lt "$filled" ]; then
            bar="${bar}${BG_FILL}${BAR_FG_FILL}${st}${content:$i:1}"
        else
            bar="${bar}${BAR_BG_EMPTY}${BAR_FG_EMPTY}${st}${content:$i:1}"
        fi
    done
    printf '%s%s' "$bar" "$RESET"
}

# Fill tracks the percentage; the label reports the count in thousands.
ctx_used_k=$(( ctx_used / 1000 ))
ctx_bar=$(make_bar "$ctx_pct" -1 "${ctx_used_k}k")

# --- Claude.ai rate limits ---
now=${EPOCHSECONDS:-$(date +%s)}

# Format seconds remaining as "Xd Yh", "Xh", or "Xm"
format_remaining() {
    if [ -z "$1" ] || ! [ "$1" -gt 0 ] 2>/dev/null; then
        echo "-"
        return
    fi
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
    if [ -z "$reset_at" ] || ! [ "$reset_at" -gt 0 ] 2>/dev/null; then
        echo -1
        return
    fi
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

five_h_part=" ${SEP} ${DIM}${COLOR_KEY}5h${RESET} ${five_h_bar} ${DIM}${five_h_remaining}${RESET}"
seven_d_part=" ${SEP} ${DIM}${COLOR_KEY}7d${RESET} ${seven_d_bar} ${DIM}${seven_d_remaining}${RESET}"

# --- Reasoning effort ---
# Absent from the input when the active model has no effort parameter; omit the
# segment entirely in that case. Reads as part of the model segment, so it shares
# the model's colour and carries no leading separator.
effort_part=""
if [ -n "$effort" ]; then
    # Leading RESET clears the model's bold, which is still in effect.
    effort_part=" ${RESET}${COLOR_CLAUDE}${effort}${RESET}"
fi

# --- Workspace and worktree lines ---
field() { printf '%s%s%s %s' "${DIM}${COLOR_KEY}" "$1" "${RESET}" "${DIM}${2}${RESET}"; }

# $HOME quoted on both sides of the match so a value containing glob characters
# is compared literally.
abbrev_home() {
    local p="$1"
    if [ -n "$HOME" ] && [ "$HOME" != "/" ] && [[ $p == "$HOME" || $p == "$HOME"/* ]]; then
        p="~${p#"$HOME"}"
    fi
    printf '%s' "$p"
}

# A linked worktree has a per-worktree git dir distinct from the shared common
# dir; a normal clone's main working tree has the two equal. Paths forced
# absolute so the comparison holds regardless of where git reports from.
#
# Also sets $wt_branch. The rev-parse that classifies the checkout reports HEAD
# in the same pass, so the branch costs no extra process. It has to come from
# git: the input JSON's nearest equivalent, .workspace.git_worktree, is the
# worktree's registered name under .git/worktrees, which git seeds from the
# directory name and never updates to track the branch.
in_linked_worktree() {
    local dir=$1 git_dir="" common_dir=""
    wt_branch=""
    [ -d "$dir" ] || return 1
    { read -r git_dir; read -r common_dir; read -r wt_branch; } < <(
        cd "$dir" 2>/dev/null &&
            git rev-parse --path-format=absolute --git-dir --git-common-dir \
                --abbrev-ref HEAD 2>/dev/null
    )
    [ -n "$git_dir" ] && [ "$git_dir" != "$common_dir" ]
}

# Only worth the vertical space where the paths disambiguate which checkout is
# live. Everywhere else the status stays a single line.
extra_lines=""
if in_linked_worktree "$ws_dir"; then
    # A detached HEAD abbreviates to the literal "HEAD", which identifies
    # nothing. The short SHA is the only handle left, and the extra process
    # to get it stays confined to that rare case.
    if [ "$wt_branch" = "HEAD" ]; then
        wt_branch=$(cd "$ws_dir" 2>/dev/null && git rev-parse --short HEAD 2>/dev/null)
        wt_branch="detached ${wt_branch:-?}"
    fi

    ws_dir=$(abbrev_home "$ws_dir")

    # Branch first: it is the volatile field, and the path under it already
    # ends in the worktree's registered name.
    lines=()
    [ -n "$wt_branch" ] && lines+=("$(field '' "$wt_branch")")
    lines+=("${DIM}${ws_dir}${RESET}")

    extra_lines=$(printf '\n%s' "${lines[@]}")
fi

# --- Output ---
printf '%s%s%s%s %s %s%s%s%s' \
    "$BOLD" "$COLOR_CLAUDE" "$model" \
    "$effort_part" \
    "$SEP" \
    "${DIM}${COLOR_KEY}${RESET} ${ctx_bar}" \
    "$five_h_part" \
    "$seven_d_part" \
    "$extra_lines"
