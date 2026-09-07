#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

HOOK="$DOTFILES_ROOT/claude/hooks/block-file-deletions.sh"

# Feed a PreToolUse(Bash) payload for $1 into the hook. Sets $output/$status
# via bats `run`. The hook always exits 0 (it fails open and deny() exits 0),
# so decisions are read from stdout, not the exit code.
run_hook() {
  local payload
  payload="$(jq -Rn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}')"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

# ─── deletions are denied in every spelling ─────────────────────────────────────

@test "denies deletion across invocation spellings" {
  local cmds=(
    'rm x'
    'rm -rf /tmp/x'
    'rmdir /tmp/d'
    'rm'
    'git rm foo'
    'sudo rm x'
    '/bin/rm x'
    '/usr/bin/rm x'
    'echo x | xargs rm'
    'find . -name "*.log" -exec rm {} \;'
    'cd foo && rm x'
    'rm x; echo done'
    'ls && (rm x)'
    '`rm x`'
  )
  for c in "${cmds[@]}"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
    if [[ "$output" != *'"deny"'* ]]; then
      echo "expected DENY but got ALLOW for: $c"
      return 1
    fi
  done
}

# The gaps that existed while this hook lived at claude/block-file-deletions.sh
# with no test. A quote was not a token boundary, so anything inside `bash -c
# "..."` read as one word; and the leading path was pinned to /bin and /usr/bin,
# so a deletion binary anywhere else went unseen.
@test "denies deletion quoted inside an interpreter invocation" {
  local cmds=(
    'bash -c "rm -rf /tmp/x"'
    "sh -c 'rm x'"
    'zsh -c "rm x"'
    'eval "rm x"'
    'bash -c "find . -delete"'
  )
  for c in "${cmds[@]}"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
    if [[ "$output" != *'"deny"'* ]]; then
      echo "expected DENY but got ALLOW for: $c"
      return 1
    fi
  done
}

@test "denies deletion binaries outside /bin and /usr/bin" {
  local cmds=(
    '/opt/homebrew/bin/rm x'
    '$HOME/bin/rm x'
    './bin/rm x'
    '../tools/bin/rmdir d'
    '/usr/local/bin/rm -f x'
    '/usr/bin/find . -delete'
  )
  for c in "${cmds[@]}"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
    if [[ "$output" != *'"deny"'* ]]; then
      echo "expected DENY but got ALLOW for: $c"
      return 1
    fi
  done
}

@test "denies find -delete and leaves other find invocations alone" {
  run_hook 'find . -delete'
  [[ "$output" == *'"deny"'* ]] || fail "expected DENY for: find . -delete"

  run_hook 'find /tmp -name "*.log" -mtime +7 -delete'
  [[ "$output" == *'"deny"'* ]] || fail "expected DENY for a filtered -delete"

  run_hook "find . -name '*.log'"
  [ -z "$output" ] || fail "expected ALLOW for a find with no deletion"
}

# ─── commands that merely contain the letters are left alone ────────────────────

# The token has to be delimited on both sides. Without that, every word with an
# "rm" in it - terraform, confirm, platform - would be denied, and a guard that
# blocks ordinary work gets switched off.
@test "allows commands that merely contain the letters rm" {
  local cmds=(
    'terraform apply'
    'npm run build'
    'storm --platform x'
    'echo alarm'
    './scripts/perform.sh'
    '/usr/bin/confirm x'
    'cd /home/warm && ls'
    'git commit -m "form review"'
    'mv x /tmp/'
    'trash x'
    'git push origin main'
    'ls -la'
  )
  for c in "${cmds[@]}"; do
    run_hook "$c"
    [ "$status" -eq 0 ]
    if [[ "$output" == *'"deny"'* ]]; then
      echo "expected ALLOW but got DENY for: $c"
      return 1
    fi
  done
}

# ─── deny payload shape ─────────────────────────────────────────────────────────

@test "a denial emits a well-formed PreToolUse deny decision" {
  run_hook 'rm -rf /tmp/x'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PreToolUse" ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *"delete files"* ]]
}

# The reason is what the agent reads to decide what to do next. AGENTS.md wants
# the deletion handed to the user, so the text has to say so.
@test "the denial reason tells the agent to hand the deletion over" {
  run_hook 'rm -rf /tmp/x'
  local reason
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")"
  [[ "$reason" == *"handed to the user"* ]]
  [[ "$reason" == *"absolute paths"* ]]
}

@test "an allowed command produces no output" {
  run_hook 'ls -la'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── resilience / fail-open ─────────────────────────────────────────────────────

@test "a non-Bash tool is ignored" {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ \
    '{"tool_name":"Read","tool_input":{"file_path":"rm -rf /"}}' "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "an empty command is allowed" {
  run_hook ''
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "a malformed payload fails open rather than blocking Bash" {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ '{bad json' "$HOOK"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}
