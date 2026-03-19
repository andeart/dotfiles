# Statusline Updates — Design Spec
_2026-03-18_

## Overview

Three targeted changes to `claude/statusline-command.sh`:

1. Fix dir/branch colors to match the active `headline.zsh-theme` styling
2. Restyle the git section to match headline's symbols, separator, and status format
3. Add a timing segment at the end showing API duration and total session duration

---

## 1. Color Fixes

### Changes

| Element | Current | New |
|---------|---------|-----|
| Directory (`COLOR_DIR`) | `\033[38;5;12m` (256-color bright blue) | `\033[1;34m` (bold ANSI blue) |
| Git branch/status (`COLOR_GIT`) | `\033[38;5;11m` (256-color bright yellow) | `\033[1;36m` (bold ANSI cyan) |

The headline theme defines these as `%{$bold$blue%}` for PATH and `%{$bold$cyan%}` for BRANCH, which map to standard ANSI `\e[1;34m` and `\e[1;36m` respectively.

Both variables (`COLOR_DIR` and `COLOR_GIT`) are referenced in multiple places in the script — changing the variable assignments at the top is sufficient; no individual sub-string edits are needed.

Also **remove** the following variables, which become dead code:
- `COLOR_DIRTY` (replaced by unified status brackets)
- `COLOR_AHEAD` (ahead/behind now styled via `COLOR_STATUS`)
- `COLOR_BEHIND` (same)

---

## 2. Git Section Restyle

### Separator between directory and branch

Replace the `⊢` connector with headline's `_SPACER` style:

| Current | New |
|---------|-----|
| ` ⊢ ` | ` \| ` styled as faint gray (`\033[2;38;5;245m`) |

### Branch display

**On a branch:** show the branch name as before, styled `BOLD + COLOR_GIT`.

**Detached HEAD:** show `:short-hash` (colon-prefixed, matching headline's `headline-git-branch` function line 325), styled the same way.

### Status brackets

Append git status after the branch name using headline's format: `[count+symbol|count+symbol]`

- **Brackets** `[` `]` and **internal separator** `|`: faint gray (`\033[2;38;5;245m`)
- **Symbols and counts**: bold magenta (`\033[1;35m`), matching headline's `%{$bold$magenta%}` STATUS color
- **Format**: `count` then `symbol` (e.g., `3!`, `2↑`) — matching headline's `"${counts[$key]}${HL_GIT_STATUS_SYMBOLS[$key]}"` (line 410)
- **Count mode**: always show count (`HL_GIT_COUNT_MODE='on'`)
- Only include an entry when its count is > 0
- If all counts are 0 (clean), omit the brackets entirely: just show the branch name

### Status symbols and order

Match headline's `HL_GIT_STATUS_ORDER` and `HL_GIT_STATUS_SYMBOLS` exactly:

Iterate over all 9 keys in `HL_GIT_STATUS_ORDER` order — including DIVERGED and CLEAN — skipping any with count = 0:

| Order | Symbol | Meaning | Notes |
|-------|--------|---------|-------|
| 1 | `+` | Staged | |
| 2 | `!` | Changed (unstaged) | |
| 3 | `?` | Untracked | |
| 4 | `↓` | Behind remote | |
| 5 | `↑` | Ahead of remote | |
| 6 | `↕` | Diverged | Dead code — `git status --porcelain -b` never emits the literal word "diverged"; this count is always 0 and never produces output. Include in iteration to match headline exactly. |
| 7 | `*` | Stashed | |
| 8 | `✘` | Conflicts | |
| 9 | _(none)_ | Clean | No symbol; handled by the "omit brackets when all counts are 0" rule. |

When both BEHIND and AHEAD are non-zero (diverged branch), `↓N` and `↑N` appear separately in that order — the actual headline behavior.

### Git data source: single `git status --porcelain -b` call

Use one call (matching headline's `headline-git-status-counts`), parsing both the tracking line and status lines:

**Tracking line** (`##`): parse `[ahead N, behind M]` with regex `(behind|ahead) ([0-9]+)` to extract BEHIND and AHEAD counts.

**Status lines** (priority order — process each line top to bottom, applying the first matching rule):

1. Skip lines matching `^##` or `^!!`
2. **Conflicts** — matches `^U[ADU]|^[AD]U|^AA|^DD`: increment CONFLICTS
3. **Untracked** — matches `^\?\?`: increment UNTRACKED
4. **Staged only** — matches `^[MTADRC] ` (non-space first char, space second): increment STAGED
5. **Both staged and changed** — matches `^[MTARC][MTD]`: increment both STAGED and CHANGED
6. **Changed only** — matches `^ [MTADRC]`: increment CHANGED

**Stash**: check `git rev-parse --verify refs/stash` — if it exists, count via `git rev-list --walk-reflogs --count refs/stash`.

**No upstream configured**: the `##` line omits the `[...]` tracking section; AHEAD and BEHIND stay 0 and are not shown. No special indicator needed.

---

## 3. Timing Segment

### Layout

Append a new `│`-separated segment **at the end**, after the context window:

```
... │ Context ◼◻◻◻◻◻◻◻◻◻ 12% (25k/200k) │ ⏱ 1m 23s / 2m 04s
```

### Fields

| Value | JSON path | Meaning |
|-------|-----------|---------|
| API duration (left) | `cost.total_api_duration_ms` | Total ms spent waiting for API responses |
| Total duration (right) | `cost.total_duration_ms` | Total wall-clock ms since session started |

### Format

- Convert ms → `Xm YYs` (minutes unpadded, seconds zero-padded to 2 digits: e.g. `0m 04s`, `2m 30s`)
- If duration exceeds 59m 59s, switch to `Xh Ym YYs` (hours and minutes both unpadded, seconds zero-padded: e.g. `1h 2m 04s`)
- Use `// 0` jq fallbacks. Omit the entire timing segment when **`total_duration_ms` is 0** — this covers the pre-API-call state where no time has elapsed yet
- If `total_duration_ms` is non-zero but `total_api_duration_ms` is 0 (e.g. before the first API response), show `0m 00s` for the API value: `⏱ 0m 00s / 1m 04s`

### Styling

| Element | Style |
|---------|-------|
| `⏱` icon + both duration values | Bold soft orange `\033[38;5;215m` |
| `/` separator between the two values | Faint gray `\033[2;38;5;245m` |

---

## Final Layout

**Clean repo, no timing yet:**
```
~/code/dotfiles | main │ Claude Sonnet 4.6 │ Context ◼◻◻◻◻◻◻◻◻◻ 12% (25k/200k)
```

**With git status and timing:**
```
~/code/dotfiles | main [2↑|3!|1?] │ Claude Sonnet 4.6 │ Context ◼◻◻◻◻◻◻◻◻◻ 12% (25k/200k) │ ⏱ 1m 23s / 2m 04s
```

**Detached HEAD:**
```
~/code/dotfiles | :abc1234 [1!] │ Claude Sonnet 4.6 │ Context ◼◻◻◻◻◻◻◻◻◻ 12% (25k/200k) │ ⏱ 1m 23s / 2m 04s
```

---

## Out of Scope

- Username / hostname not added to statusline
- Token count fields (`current_usage`, `output_tokens`) not changed
- No other visual or structural changes
