#!/usr/bin/env bash
#
# Git clean/smudge filter for iTerm2 plist.
#
# clean:  working tree (binary plist) → repo (cleaned XML)
#         Strips transient state, replaces $HOME with __HOME__
# smudge: repo (cleaned XML) → working tree (binary plist)
#         Resolves __HOME__ to $HOME
#
# Usage (called by git, configured via filter.iterm-plist):
#   iterm-filter.sh clean
#   iterm-filter.sh smudge

set -euo pipefail

MODE="${1:?Usage: iterm-filter.sh clean|smudge}"

TEMP_IN=$(mktemp) || exit 1
TEMP_OUT=$(mktemp) || { rm -f "$TEMP_IN"; exit 1; }
trap 'rm -f "$TEMP_IN" "$TEMP_OUT"' EXIT

cat > "$TEMP_IN"

if [ "$MODE" = "smudge" ]; then
    # XML from repo → resolve __HOME__ → binary plist for iTerm
    sed "s|__HOME__|$HOME|g" "$TEMP_IN" > "$TEMP_OUT"
    plutil -convert binary1 -o - "$TEMP_OUT"
    exit 0
fi

if [ "$MODE" = "clean" ]; then
    # Binary plist from working tree → cleaned XML for repo

    # Convert to XML (handles both binary and XML input)
    plutil -convert xml1 -o "$TEMP_OUT" "$TEMP_IN"
    cp "$TEMP_OUT" "$TEMP_IN"

    # Helper: delete a key, silently ignoring if missing
    plist_del() { /usr/libexec/PlistBuddy -c "Delete ':$1'" "$TEMP_IN" 2>/dev/null || true; }

    # Helper: list all top-level keys matching a prefix.
    # PlistBuddy "Print" indents top-level keys with 4 spaces and appends " = <value>".
    # We extract just the key name. LC_ALL=C handles non-UTF8 bytes in values.
    plist_keys() {
        local pattern="$1"
        # `|| true` so pipefail doesn't propagate a PlistBuddy failure
        # (e.g. unexpected plist state) up into the caller's while loop.
        LC_ALL=C /usr/libexec/PlistBuddy -c "Print" "$TEMP_IN" 2>/dev/null \
            | LC_ALL=C sed -nE "s/^    ($pattern.*) = .*$/\1/p" || true
    }

    # --- Strip top-level keys by pattern ---

    plist_keys 'A[Ii]' | while IFS= read -r key; do plist_del "$key"; done
    plist_keys 'NS'     | while IFS= read -r key; do plist_del "$key"; done
    plist_keys 'NoSync' | while IFS= read -r key; do plist_del "$key"; done
    plist_keys 'Apple'  | while IFS= read -r key; do plist_del "$key"; done
    plist_keys 'SU'     | while IFS= read -r key; do plist_del "$key"; done

    # Specific deprecated keys
    for key in HotkeyMigratedFromSingleToMulti ShowFullScreenTabBar; do
        plist_del "$key"
    done

    # --- Strip deprecated keys from all profiles ---

    i=0
    while /usr/libexec/PlistBuddy -c "Print ':New Bookmarks:$i:Name'" "$TEMP_IN" &>/dev/null; do
        for key in "BM Growl" "Sync Title" "Thin Strokes"; do
            /usr/libexec/PlistBuddy -c "Delete ':New Bookmarks:$i:$key'" "$TEMP_IN" 2>/dev/null || true
        done
        # Pre-increment form (`++i` expands to the new, non-zero value) so the
        # arithmetic command doesn't exit 1 on the first iteration when i was 0,
        # which would otherwise trip `set -e`.
        ((++i))
    done

    # --- Replace $HOME with placeholder ---

    LC_ALL=C sed -i '' "s|$HOME|__HOME__|g" "$TEMP_IN"

    # Output cleaned XML
    cat "$TEMP_IN"
    exit 0
fi

echo "Usage: iterm-filter.sh clean|smudge" >&2
exit 1
