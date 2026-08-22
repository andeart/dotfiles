#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

CONFIG="$DOTFILES_ROOT/.gitleaks.toml"
KEYBINDINGS="$DOTFILES_ROOT/vscode/keybindings.json"

# The one chord in the file whose entropy clears generic-api-key's threshold,
# and so the only value .gitleaks.toml exempts.
CHORD='shift+alt+down'

# Assembled rather than written out, so this file does not trip the scanner it
# is testing. Long mixed-case literals are what generic-api-key exists to catch.
TOKEN="hT8fQz3X""mL9vRp2W""bN6kYs4J""dC7gAeU1"
# The same length in lowercase and digits only. A character class permissive
# enough to spell chords can wave this through while still excluding mixed
# case, so the mixed-case token alone does not prove the allowlist is narrow.
LOWER_TOKEN="a3f9c2e7""b1d84a6f""0c5e93b7""d2148f6a"
# The same characters again, split into chord-shaped runs. "+" is inside
# generic-api-key's base64 class, so the runs join rather than terminate and
# the whole value is still one finding - which an allowlist that bounds each
# run separately would wave through.
SPLIT_TOKEN="a3f9c2e7b1d""+""84a6f0c5e93""+""b7d2148f6ac"

# The pinned gitleaks pre-commit hook's entry, plus --no-banner/--no-color for
# stable output. No --config: the point of these tests is that .gitleaks.toml
# is found on its own.
scan_staged() {
  run gitleaks git --pre-commit --redact --staged --verbose --no-banner --no-color
}

# The tier CI runs, over everything in the probe repo's history.
scan_history() {
  run gitleaks git --redact --verbose --no-banner --no-color
}

# A git repo holding the real .gitleaks.toml and keybindings.json, with both
# already committed so later edits show up as a staged diff. Leaves the shell
# inside it.
probe_repo() {
  local probe
  probe="$(mktemp -d)"
  mkdir -p "$probe/vscode"
  cp "$CONFIG" "$probe/.gitleaks.toml"
  cp "$KEYBINDINGS" "$probe/vscode/keybindings.json"
  cd "$probe"
  git init -q .
  git add -A
  git commit -q -m "baseline"
}

# Splice an entry into the head of the keybindings array, taking the entry's
# lines as arguments.
splice_entry() {
  python3 - "$@" <<'PY'
import sys

path = 'vscode/keybindings.json'
lines = open(path).read().split('\n')
entry = sys.argv[1:]
head = next(i for i, l in enumerate(lines) if l.strip().startswith('['))
open(path, 'w').write('\n'.join(lines[:head + 1] + entry + lines[head + 1:]))
PY
}

# Stage $1 as a keybinding's "key" value and assert generic-api-key still
# reports it. The surrounding entry is otherwise a plausible binding, so a
# finding can only come from the value itself.
assert_key_value_reported() {
  probe_repo
  splice_entry \
    '    {' \
    "        \"key\": \"$1\"," \
    '        "command": "extension.run"' \
    '    },'
  git add vscode/keybindings.json

  scan_staged
  [ "$status" -ne 0 ]
  [[ "$output" == *"generic-api-key"* ]]
}

# ─── the chords stay suppressed ────────────────────────────────────────────

@test "the committed keybindings file scans clean through history" {
  probe_repo
  scan_history
  [ "$status" -eq 0 ]
  [[ "$output" == *"no leaks found"* ]]
}

@test "a whole-file rewrite reintroduces no findings" {
  probe_repo
  # Reindent the whole file so every chord lands in one staged diff. An
  # exemption that happened to cover only one chord would fail here.
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

@test "the exempted chord is the only value in the file that fires" {
  probe_repo
  # Drop the exemption and see what the rule reports unaided. Every finding has
  # to be the chord .gitleaks.toml names: another value here means the
  # exemption is too narrow, and no findings at all mean it is dead config
  # kept alive by nothing.
  python3 -c "
p = '.gitleaks.toml'
config = open(p).read()
open(p, 'w').write(config.split('[[allowlists]]')[0])
"
  # Unredacted, so the assertion can compare the values themselves. The probe
  # repo holds only chords, so there is nothing here to leak into test output.
  run gitleaks git --verbose --no-banner --no-color
  [ "$status" -ne 0 ]
  [ "$(grep '^Secret:' <<< "$output" | awk '{print $2}' | sort -u)" = "$CHORD" ]
}

# ─── real secrets still get through ────────────────────────────────────────

@test "a secret elsewhere in the keybindings file is still reported" {
  probe_repo
  splice_entry \
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
  assert_key_value_reported "$TOKEN"
}

@test "a lowercase token parked in a key field is still reported" {
  assert_key_value_reported "$LOWER_TOKEN"
}

@test "a token split into chord-shaped runs is still reported" {
  assert_key_value_reported "$SPLIT_TOKEN"
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
