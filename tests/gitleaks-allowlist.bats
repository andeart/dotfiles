#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

CONFIG="$DOTFILES_ROOT/.gitleaks.toml"
KEYBINDINGS="$DOTFILES_ROOT/vscode/keybindings.json"

CHORD='shift+alt+down'
# Assembled rather than written out, so this file does not trip the scanner it
# is testing. Long mixed-case literals are what generic-api-key exists to catch.
TOKEN="hT8fQz3X""mL9vRp2W""bN6kYs4J""dC7gAeU1"

# The entry the pinned gitleaks pre-commit hook runs, verbatim. No --config:
# the point of these tests is that .gitleaks.toml is found on its own.
scan_staged() {
  run gitleaks git --pre-commit --redact --staged --verbose --no-banner --no-color
}

# The tier CI runs, over everything in the probe repo's history.
scan_history() {
  run gitleaks git --redact --verbose --no-banner --no-color
}

# A git repo holding the real .gitleaks.toml and keybindings.json, with both
# already committed so later edits show up as a staged diff. Leaves $PROBE set
# and the shell inside it.
probe_repo() {
  PROBE="$(mktemp -d)"
  mkdir -p "$PROBE/vscode"
  cp "$CONFIG" "$PROBE/.gitleaks.toml"
  cp "$KEYBINDINGS" "$PROBE/vscode/keybindings.json"
  cd "$PROBE"
  git init -q .
  git add -A
  git commit -q -m "baseline"
}

# Insert a keybinding entry at the head of the array.
insert_entry() {
  python3 - "$@" <<'PY'
import sys
p, entry = sys.argv[1], sys.argv[2:]
lines = open(p).read().split('\n')
idx = next(i for i, l in enumerate(lines) if l.strip().startswith('['))
open(p, 'w').write('\n'.join(lines[:idx + 1] + entry + lines[idx + 1:]))
PY
}

# ─── the chords stay suppressed ────────────────────────────────────────────

@test "the committed keybindings file scans clean through history" {
  probe_repo
  scan_history
  [ "$status" -eq 0 ]
  [[ "$output" == *"no leaks found"* ]]
}

@test "a rewrite that moves the chord lines does not reintroduce findings" {
  probe_repo
  # Move the first chord block to the top of the array, so those lines land in
  # the diff as additions at line numbers nothing has ever pinned.
  python3 - "$CHORD" <<'PY'
import sys
p = 'vscode/keybindings.json'
lines = open(p).read().split('\n')
start = next(i for i, l in enumerate(lines) if sys.argv[1] in l) - 1
end = start
while '},' not in lines[end]:
    end += 1
block, rest = lines[start:end + 1], lines[:start] + lines[end + 1:]
idx = next(i for i, l in enumerate(rest) if l.strip().startswith('['))
open(p, 'w').write('\n'.join(rest[:idx + 1] + block + rest[idx + 1:]))
PY
  git add vscode/keybindings.json
  # The rewrite has to actually re-add the chord, or the scan proves nothing.
  run git diff --cached
  [[ "$output" == *"+"*'"key": "'"$CHORD"* ]]

  scan_staged
  [ "$status" -eq 0 ]
  [[ "$output" == *"no leaks found"* ]]
}

@test "every key line in the real file is covered by the allowlist" {
  probe_repo
  # Reindent the whole file so every chord lands in one staged diff. A regex
  # that happened to cover only one chord would fail here.
  python3 -c "
p = 'vscode/keybindings.json'
open(p, 'w').write('\n'.join(' ' + l if l else l for l in open(p).read().split('\n')))
"
  git add vscode/keybindings.json

  scan_staged
  [ "$status" -eq 0 ]
  [[ "$output" == *"no leaks found"* ]]
}

# ─── real secrets still get through ────────────────────────────────────────

@test "a secret elsewhere in the keybindings file is still reported" {
  probe_repo
  insert_entry vscode/keybindings.json \
    '    {' \
    '        "key": "ctrl+k q",' \
    '        "command": "extension.run",' \
    "        \"args\": { \"api_key\": \"$TOKEN\" }" \
    '    },'
  git add vscode/keybindings.json

  scan_staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"generic-api-key"* ]]
}

@test "a token parked in a key field is still reported" {
  probe_repo
  insert_entry vscode/keybindings.json \
    '    {' \
    "        \"key\": \"$TOKEN\"," \
    '        "command": "extension.run"' \
    '    },'
  git add vscode/keybindings.json

  scan_staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"generic-api-key"* ]]
}

@test "the allowlist does not reach a chord in another file" {
  probe_repo
  mkdir -p other
  cp vscode/keybindings.json other/keybindings.json
  git add other/keybindings.json

  scan_staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"other/keybindings.json"* ]]
}

# ─── no going back to fingerprints ─────────────────────────────────────────

@test "no commit-pinned fingerprints are left in the repo" {
  # The file may be gone entirely; what matters is that nothing pins a commit.
  run grep -c "vscode/keybindings.json" "$DOTFILES_ROOT/.gitleaksignore"
  [ "$status" -ne 0 ]
}
