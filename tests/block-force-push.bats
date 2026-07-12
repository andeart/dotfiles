#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

HOOK="$DOTFILES_ROOT/claude/block-force-push.sh"

# Feed a PreToolUse(Bash) payload for $1 into the hook. Sets $output/$status
# via bats `run`. The hook always exits 0 (it fails open and deny() exits 0),
# so decisions are read from stdout, not the exit code.
run_hook() {
  local payload
  payload="$(jq -Rn --arg c "$1" '{tool_name: "Bash", tool_input: {command: $c}}')"
  run bash -c 'printf "%s" "$1" | bash "$2"' _ "$payload" "$HOOK"
}

# ─── force-push is denied in every spelling ─────────────────────────────────────

@test "denies force-push across flag and refspec spellings" {
  local cmds=(
    'git push --force'
    'git push -f'
    'git push --force origin main'
    'git push origin main --force'
    'git push --force-with-lease'
    'git push --force-with-lease=origin/main'
    'git push --force-if-includes origin'
    'git push origin +main'
    'git push origin +refs/heads/main:refs/heads/main'
    'git -C /repo push --force'
    'git --no-pager push -f origin live'
    'cd foo && git push --force'
    'git push --force;'
    'git push -fu origin main'
    'git push -uf origin main'
    'git push --set-upstream -f origin x'
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

# ─── legitimate commands are left alone ─────────────────────────────────────────

@test "allows normal pushes and --force on other subcommands" {
  local cmds=(
    'git push'
    'git push origin main'
    'git push -u origin main'
    'git push --set-upstream origin main'
    'git push --tags'
    'git push --follow-tags origin main'
    'git push -n origin main'
    'git fetch --all --prune --tags --force'
    'git fetch --force && git push origin main'
    'git clean -fd'
    'git checkout --force main'
    'git branch -f foo bar'
    'code --install-extension x --force'
    'git commit -m "force push discussion"'
    'git commit -m "use --force-with-lease carefully"'
    'rm -f x && git push origin main'
    'git log --oneline'
    'echo pushing'
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
  run_hook 'git push --force'
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PreToolUse" ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *"force-push"* ]]
}

@test "an allowed command produces no output" {
  run_hook 'git push origin main'
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── resilience / fail-open ─────────────────────────────────────────────────────

@test "a non-Bash tool is ignored" {
  run bash -c 'printf "%s" "$1" | bash "$2"' _ \
    '{"tool_name":"Read","tool_input":{"file_path":"git push --force"}}' "$HOOK"
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
