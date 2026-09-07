#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

HOOKS="$DOTFILES_ROOT/claude/hooks"
LIB="$HOOKS/lib/claude-exe.sh"

# Build a fake $HOME carrying both hooks, the real message module, and a stub
# claude-exe.sh whose resolve_claude_exe echoes $1.
#
# The stub is what makes the hooks gradeable at all. resolve_claude_exe needs an
# ancestor process whose executable is named `claude`, and no runnable stand-in
# for that exists: macOS SIGKILLs copies of the arm64e platform binaries a test
# would use, and a script named `claude` reports its interpreter to both `ps
# -o comm=` and `lsof`, not itself. The real function's one parsing subtlety is
# covered directly by the _lsof_first_name tests below.
#
# Sets $FAKE_HOME.
stub_home() {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.claude/hooks/lib"
  cp "$HOOKS/ha-mcp-guard.sh" "$HOOKS/ha-mcp-notice.sh" "$FAKE_HOME/.claude/hooks/"
  cp "$HOOKS/lib/ha_mcp_message.py" "$FAKE_HOME/.claude/hooks/lib/"
  cat > "$FAKE_HOME/.claude/hooks/lib/claude-exe.sh" <<EOF
resolve_claude_exe() { printf '%s' '$1'; }
is_bundled_claude() {
  case "\$1" in
    *.app/Contents/MacOS/*) return 0 ;;
    *) return 1 ;;
  esac
}
EOF
}

run_hook() {
  run env HOME="$FAKE_HOME" bash "$FAKE_HOME/.claude/hooks/$1"
}

# As run_hook, with the hook's stderr dropped before bats captures it. A
# `2>/dev/null` on the `run` line redirects run's own stderr, not that of the
# command it captures, which bats merges into $output either way. The fallback
# paths below reach python without its module and print a traceback, and the
# assertion is about the decision on stdout.
run_hook_quiet() {
  run bash -c 'HOME="$1" bash "$1/.claude/hooks/$2" 2>/dev/null' _ "$FAKE_HOME" "$1"
}

BUNDLED="/Users/me/Library/Application Support/Claude/claude-code/2.1.260/claude.app/Contents/MacOS/claude"
BARE="/Users/me/.local/share/claude/versions/2.1.263"

# ─── is_bundled_claude ──────────────────────────────────────────────────────────

@test "is_bundled_claude accepts bundle paths and rejects everything else" {
  source "$LIB"
  is_bundled_claude "$BUNDLED" || fail "expected the desktop app path to read as bundled"
  is_bundled_claude "/Applications/Claude.app/Contents/MacOS/claude" || fail "expected /Applications bundle"

  ! is_bundled_claude "$BARE" || fail "expected the bare CLI path to read as unbundled"
  ! is_bundled_claude "" || fail "expected an unresolved path to read as unbundled"
  ! is_bundled_claude "/Users/me/claude.app/Contents/Resources/claude" || fail "MacOS/ is the part that matters"
}

# ─── lsof parsing ───────────────────────────────────────────────────────────────

# The desktop app's copy lives under "Application Support". lsof's default table
# puts NAME last but not as the last whitespace-delimited field, so reading $NF
# returned a path that does not exist - and the value is both what decides the
# verdict and what the denial text shows the user.
@test "_lsof_first_name keeps a path containing spaces intact" {
  run bash -c 'source "$1"; printf "%s\n" "$2" | _lsof_first_name' _ "$LIB" "n$BUNDLED"
  [ "$status" -eq 0 ]
  [ "$output" = "$BUNDLED" ]
}

@test "_lsof_first_name takes the first name and ignores other field types" {
  run bash -c 'source "$1"; printf "p123\nftxt\n%s\nn/second/path\n" "$2" | _lsof_first_name' \
    _ "$LIB" "n$BARE"
  [ "$status" -eq 0 ]
  [ "$output" = "$BARE" ]
}

@test "_lsof_first_name yields nothing when lsof returned no name" {
  run bash -c 'source "$1"; printf "p123\n" | _lsof_first_name' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# A pid with no process behind it, not the current one: this suite is itself
# run from a claude process most of the time, so walking up from $$ resolves a
# real executable and asserting emptiness there passes only off a developer's
# machine.
@test "resolve_claude_exe yields nothing when the walk finds no process" {
  run bash -c 'source "$1"; resolve_claude_exe 999999' _ "$LIB"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── the guard denies unless a bundle is positively identified ──────────────────

@test "guard allows the tools under the desktop app" {
  stub_home "$BUNDLED"
  run_hook ha-mcp-guard.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ] || fail "expected no decision (allow), got: $output"
}

@test "guard denies the tools under the bare CLI" {
  stub_home "$BARE"
  run_hook ha-mcp-guard.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PreToolUse" ]
  [[ "$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")" == *"$BARE"* ]]
}

@test "guard denies when the executable cannot be identified" {
  stub_home ""
  run_hook ha-mcp-guard.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
}

# An unresolved binary is not a known bare Mach-O. The denial is still right,
# but the reason has to say what was established rather than assert a shape
# nothing identified.
@test "the unresolved denial does not claim a bare Mach-O" {
  stub_home ""
  run_hook ha-mcp-guard.sh
  local reason
  reason="$(jq -r '.hookSpecificOutput.permissionDecisionReason' <<<"$output")"
  [[ "$reason" == *"could not be identified"* ]]
  [[ "$reason" != *"bare Mach-O"* ]]
}

# The guard's whole value is that it answers "deny" when it cannot tell. Both of
# these left it emitting nothing and exiting 0, which reads as allow - and the
# missing-lib case is exactly the un-pushed machine the hook has to survive.
@test "guard denies when the lib never synced" {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  cp "$HOOKS/ha-mcp-guard.sh" "$FAKE_HOME/.claude/hooks/"
  run_hook_quiet ha-mcp-guard.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
}

@test "guard denies when the message module is unavailable" {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.claude/hooks/lib"
  cp "$HOOKS/ha-mcp-guard.sh" "$FAKE_HOME/.claude/hooks/"
  cp "$LIB" "$FAKE_HOME/.claude/hooks/lib/"
  run_hook_quiet ha-mcp-guard.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.permissionDecision' <<<"$output")" = "deny" ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "PreToolUse" ]
}

# ─── the notice speaks only when it knows the session is the bare CLI ───────────

@test "notice is silent under the desktop app" {
  stub_home "$BUNDLED"
  run_hook ha-mcp-notice.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# The opposite default from the guard, on the same unknown. A notice that fires
# here tells the user their session is a bare Mach-O nothing established, and
# hands the model context saying the tools are blocked when they may not be.
@test "notice is silent when the executable cannot be identified" {
  stub_home ""
  run_hook ha-mcp-notice.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "notice is silent when the lib never synced" {
  FAKE_HOME="$(mktemp -d)"
  mkdir -p "$FAKE_HOME/.claude/hooks"
  cp "$HOOKS/ha-mcp-notice.sh" "$FAKE_HOME/.claude/hooks/"
  run_hook_quiet ha-mcp-notice.sh
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "notice warns under the bare CLI, to the user and to the model" {
  stub_home "$BARE"
  run_hook ha-mcp-notice.sh
  [ "$status" -eq 0 ]
  [ "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$output")" = "SessionStart" ]
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"desktop-app only"* ]]
  [[ "$(jq -r '.systemMessage' <<<"$output")" == *"$BARE"* ]]
  [[ "$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")" == *"mcp__home-assistant__"* ]]
}

# The two strings are for different readers and must not collapse into one: the
# user gets the mechanism, the model gets what to do instead.
@test "the model-facing context is not the user-facing alert" {
  stub_home "$BARE"
  run_hook ha-mcp-notice.sh
  local msg ctx
  msg="$(jq -r '.systemMessage' <<<"$output")"
  ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$output")"
  [ "$msg" != "$ctx" ]
  [[ "$ctx" == *"curl"* ]] || fail "the model-facing string should name the workaround"
}
