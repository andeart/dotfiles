#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

CONFIG="$DOTFILES_ROOT/.gitleaks.toml"
KEYBINDINGS="$DOTFILES_ROOT/vscode/keybindings.json"

CHORD='shift+alt+down'
# Assembled rather than written out, so this file does not trip the scanner it
# is testing. Long mixed-case literals are what generic-api-key exists to catch.
TOKEN="hT8fQz3X""mL9vRp2W""bN6kYs4J""dC7gAeU1"
# The same length in lowercase and digits only. A character class permissive
# enough to spell chords can wave this through while still excluding mixed
# case, so the mixed-case token alone does not prove the allowlist is narrow.
LOWER_TOKEN="a3f9c2e7""b1d84a6f""0c5e93b7""d2148f6a"

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

# Splice an entry into the head of the keybindings array. "insert" takes the
# entry's lines as arguments; "move" lifts the entry containing a substring out
# of its current position first, so its lines land in the diff as additions.
splice_entry() {
  python3 - "$@" <<'PY'
import sys

path = 'vscode/keybindings.json'
lines = open(path).read().split('\n')
mode, args = sys.argv[1], sys.argv[2:]

if mode == 'insert':
    entry, rest = args, lines
else:
    start = next(i for i, l in enumerate(lines) if args[0] in l) - 1
    end = start
    while '},' not in lines[end]:
        end += 1
    entry, rest = lines[start:end + 1], lines[:start] + lines[end + 1:]

head = next(i for i, l in enumerate(rest) if l.strip().startswith('['))
open(path, 'w').write('\n'.join(rest[:head + 1] + entry + rest[head + 1:]))
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
  splice_entry move "$CHORD"
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
lines = open(p).read().split('\n')
open(p, 'w').write('\n'.join(' ' + l if l else l for l in lines))
"
  git add vscode/keybindings.json
  # Every chord has to land in the diff as an addition, or the scan proves
  # nothing - an edit that emptied the file instead would still scan clean.
  run git diff --cached
  [ "$(grep -c '^+.*"key"' <<< "$output")" -eq "$(grep -c '"key"' "$KEYBINDINGS")" ]

  scan_staged
  [ "$status" -eq 0 ]
  [[ "$output" == *"no leaks found"* ]]
}

# ─── real secrets still get through ────────────────────────────────────────

@test "a secret elsewhere in the keybindings file is still reported" {
  probe_repo
  splice_entry insert \
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
  splice_entry insert \
    '    {' \
    "        \"key\": \"$TOKEN\"," \
    '        "command": "extension.run"' \
    '    },'
  git add vscode/keybindings.json

  scan_staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"generic-api-key"* ]]
}

@test "a lowercase token parked in a key field is still reported" {
  probe_repo
  splice_entry insert \
    '    {' \
    "        \"key\": \"$LOWER_TOKEN\"," \
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

# ─── the exemption is scoped to the one rule it exists for ─────────────────

@test "targetRules scoping is honoured by the pinned gitleaks" {
  probe_repo
  # Repoint the exemption at a different real rule. The chords must come back:
  # a gitleaks that ignored targetRules would still report nothing, and the
  # scoping in .gitleaks.toml would be doing nothing while looking like it was.
  python3 -c "
p = '.gitleaks.toml'
config = open(p).read()
open(p, 'w').write(config.replace('\"generic-api-key\"', '\"gitlab-pat\"'))
"
  scan_history
  [ "$status" -ne 0 ]
  [[ "$output" == *"generic-api-key"* ]]
}
