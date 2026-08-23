#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

BIN="$DOTFILES_ROOT/bin/gh-set-default-settings"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_GH_SETTINGS_LIB_ONLY=1 source "$0"; "$@"' "$BIN" "$@"
}

# Like call(), with OWNER_REPO set. Functions that report on an applied write
# name the repo in their failure message.
call_in_repo() {
  run bash -c '_GH_SETTINGS_LIB_ONLY=1 source "$0"; OWNER_REPO=owner/repo; "$@"' "$BIN" "$@"
}

# ─── flags & help ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: gh-set-default-settings"* ]]
}

@test "an unknown flag exits non-zero" {
  run "$BIN" --nope
  [ "$status" -ne 0 ]
}

@test "no repo argument exits non-zero" {
  run "$BIN"
  [ "$status" -ne 0 ]
}

@test "a second positional repo argument exits non-zero" {
  run "$BIN" owner/repo other/repo
  [ "$status" -ne 0 ]
}

# ─── parse_repo (pure) ─────────────────────────────────────────────────────

@test "parse_repo normalizes the git@ scp form" {
  call parse_repo "git@github.com:owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "parse_repo normalizes the https form" {
  call parse_repo "https://github.com/owner/repo.git"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

@test "parse_repo passes through the owner/repo form" {
  call parse_repo "owner/repo"
  [ "$status" -eq 0 ]
  [ "$output" = "owner/repo" ]
}

# ─── reply_is_yes (pure) ───────────────────────────────────────────────────

@test "reply_is_yes accepts y, Y, yes, YES, Yes" {
  for r in y Y yes YES Yes; do
    call reply_is_yes "$r"
    [ "$status" -eq 0 ] || { echo "rejected: $r"; return 1; }
  done
}

@test "reply_is_yes rejects empty and other input" {
  for r in "" n no maybe yep yy; do
    call reply_is_yes "$r"
    [ "$status" -ne 0 ] || { echo "accepted: $r"; return 1; }
  done
}

# ─── render_ruleset (pure) ─────────────────────────────────────────────────

BASELINE_JSON='{"name":"default baseline guard","target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"creation"},{"type":"deletion"},{"type":"required_signatures"},{"type":"non_fast_forward"},{"type":"pull_request","parameters":{"required_approving_review_count":0,"dismiss_stale_reviews_on_push":true,"require_code_owner_review":false,"require_last_push_approval":false,"required_review_thread_resolution":true,"allowed_merge_methods":["squash"]}}]}'

@test "render_ruleset shows name, target, enforcement" {
  call render_ruleset "$BASELINE_JSON"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Ruleset: default baseline guard"* ]]
  [[ "$output" == *"target:      default branch"* ]]
  [[ "$output" == *"enforcement: active"* ]]
}

@test "render_ruleset maps rule types to readable labels" {
  call render_ruleset "$BASELINE_JSON"
  [[ "$output" == *"restrict creations"* ]]
  [[ "$output" == *"restrict deletions"* ]]
  [[ "$output" == *"require signed commits"* ]]
  [[ "$output" == *"block force pushes"* ]]
  [[ "$output" == *"require pull request before merging"* ]]
}

@test "render_ruleset enumerates pull_request parameters" {
  call render_ruleset "$BASELINE_JSON"
  [[ "$output" == *"required approvals: 0"* ]]
  [[ "$output" == *"dismiss stale approvals on push: true"* ]]
  [[ "$output" == *"require conversation resolution: true"* ]]
  [[ "$output" == *"allowed merge methods: squash"* ]]
}

@test "render_ruleset shows bypass actors when present" {
  local json='{"name":"g","target":"branch","enforcement":"active","bypass_actors":[{"actor_id":5,"actor_type":"RepositoryRole","bypass_mode":"always"}],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"rules":[{"type":"update"}]}'
  call render_ruleset "$json"
  [[ "$output" == *"bypass:"* ]]
  [[ "$output" == *"RepositoryRole id 5 (always)"* ]]
  [[ "$output" == *"restrict updates"* ]]
}

# ─── ruleset_change_kind (pure) ────────────────────────────────────────────

EXISTING_RULESETS_JSON='[{"id":12345,"name":"default baseline guard"},{"id":99,"name":"other"}]'

@test "ruleset_change_kind returns update with id for an existing name" {
  call ruleset_change_kind "default baseline guard" "$EXISTING_RULESETS_JSON"
  [ "$status" -eq 0 ]
  [ "$output" = "update 12345" ]
}

@test "ruleset_change_kind returns create for an absent name" {
  call ruleset_change_kind "default PR approval guard" "$EXISTING_RULESETS_JSON"
  [ "$status" -eq 0 ]
  [ "$output" = "create" ]
}

@test "ruleset_change_kind returns create against an empty list" {
  call ruleset_change_kind "anything" "[]"
  [ "$status" -eq 0 ]
  [ "$output" = "create" ]
}

# ─── repo_settings_diff (pure) ─────────────────────────────────────────────

FLAT_OFF='"allow_auto_merge":false,"allow_update_branch":false,"delete_branch_on_merge":false'
FLAT_ON='"allow_auto_merge":true,"allow_update_branch":true,"delete_branch_on_merge":true'
SA_ON='"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"},"secret_scanning_non_provider_patterns":{"status":"enabled"}}'
SA_OFF='"security_and_analysis":{"secret_scanning":{"status":"disabled"},"secret_scanning_push_protection":{"status":"disabled"},"secret_scanning_non_provider_patterns":{"status":"disabled"}}'
OWNER_ORG='"owner":{"type":"Organization"}'
OWNER_USER='"owner":{"type":"User"}'

@test "repo_settings_diff flags fields that are currently false" {
  local cur="{$FLAT_OFF,\"private\":false,$SA_OFF}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"allow_auto_merge"* ]]
  [[ "$output" == *"allow_update_branch"* ]]
  [[ "$output" == *"false -> true (would change)"* ]]
  [[ "$output" == *"delete_branch_on_merge"* ]]
}

@test "repo_settings_diff reports no change when already true" {
  local cur="{$FLAT_ON,\"private\":false,$SA_ON}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"true (no change)"* ]]
  [[ "$output" != *"would change"* ]]
}

# ─── repo_settings_diff: security settings (pure) ──────────────────────────

@test "repo_settings_diff flags security settings that are currently disabled" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,$SA_OFF}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning:"* ]]
  [[ "$output" == *"secret_scanning_push_protection:"* ]]
  [[ "$output" == *"disabled -> enabled (would change)"* ]]
}

@test "repo_settings_diff reports no change when security settings are already enabled" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,$SA_ON}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning:"* ]]
  [[ "$output" == *"enabled (no change)"* ]]
  [[ "$output" != *"would change"* ]]
}

@test "repo_settings_diff treats an absent security_and_analysis as a change" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,\"security_and_analysis\":null}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"null -> enabled (would change)"* ]]
}

@test "repo_settings_diff skips security settings on a private repo" {
  local cur="{$FLAT_ON,\"private\":true,\"security_and_analysis\":null}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning:"* ]]
  [[ "$output" == *"skipped (private repo - needs GitHub Secret Protection)"* ]]
  [[ "$output" != *"would change"* ]]
}

@test "repo_settings_diff still diffs the flat settings on a private repo" {
  local cur="{$FLAT_OFF,\"private\":true,\"security_and_analysis\":null}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"false -> true (would change)"* ]]
}

@test "repo_settings_diff keeps the widest field name aligned with the rest" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,$SA_ON}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  # Every line pads the label to the same column, so the values line up.
  run bash -c 'awk "{ print index(\$0, \$2) }" <<< "$1" | sort -u | wc -l' _ "$output"
  [ "$output" -eq 1 ]
}

@test "repo_settings_diff flags non-provider patterns on an organization-owned repo" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,$SA_OFF}" line
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  line="$(grep secret_scanning_non_provider_patterns <<< "$output")"
  [[ "$line" == *"disabled -> enabled (would change)"* ]]
}

@test "repo_settings_diff skips non-provider patterns on a personal-account repo" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_USER,$SA_OFF}" line
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  line="$(grep secret_scanning_non_provider_patterns <<< "$output")"
  [[ "$line" == *"skipped (personal-account repo - needs an organization-owned repo)"* ]]
}

@test "repo_settings_diff still diffs the other security settings on a personal-account repo" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_USER,$SA_OFF}" line
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  line="$(grep "secret_scanning_push_protection" <<< "$output")"
  [[ "$line" == *"disabled -> enabled (would change)"* ]]
}

@test "repo_settings_diff reports the private-repo reason for every security setting" {
  local cur="{$FLAT_ON,\"private\":true,$OWNER_ORG,\"security_and_analysis\":null}" line
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  line="$(grep secret_scanning_non_provider_patterns <<< "$output")"
  [[ "$line" == *"skipped (private repo - needs GitHub Secret Protection)"* ]]
}

@test "repo_settings_diff reports no change when non-provider patterns are already enabled" {
  local cur="{$FLAT_ON,\"private\":false,$OWNER_ORG,$SA_ON}" line
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  line="$(grep secret_scanning_non_provider_patterns <<< "$output")"
  [[ "$line" == *"enabled (no change)"* ]]
}

# ─── non_provider_patterns_available (pure) ────────────────────────────────

@test "non_provider_patterns_available accepts an organization-owned repo" {
  call non_provider_patterns_available '{"owner":{"type":"Organization"}}'
  [ "$status" -eq 0 ]
}

@test "non_provider_patterns_available rejects a personal-account repo" {
  call non_provider_patterns_available '{"owner":{"type":"User"}}'
  [ "$status" -ne 0 ]
}

# ─── security_settings_available (pure) ────────────────────────────────────

@test "security_settings_available accepts a public repo" {
  call security_settings_available '{"private":false}'
  [ "$status" -eq 0 ]
}

@test "security_settings_available rejects a private repo" {
  call security_settings_available '{"private":true}'
  [ "$status" -ne 0 ]
}

# ─── assert_applied (pure) ─────────────────────────────────────────────────

@test "assert_applied passes silently when the API echoed the requested value" {
  call_in_repo assert_applied secret_scanning enabled enabled
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "assert_applied passes for a flat setting echoed as true" {
  call_in_repo assert_applied allow_auto_merge true true
  [ "$status" -eq 0 ]
}

@test "assert_applied fails naming the field, the value seen, and the value wanted" {
  call_in_repo assert_applied secret_scanning disabled enabled
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret_scanning"* ]]
  [[ "$output" == *"is 'disabled', not 'enabled'"* ]]
  [[ "$output" == *"owner/repo"* ]]
}

@test "assert_applied fails when the field is absent from the response" {
  call_in_repo assert_applied secret_scanning_push_protection null enabled
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret_scanning_push_protection"* ]]
  [[ "$output" == *"is 'null', not 'enabled'"* ]]
}

@test "assert_applied fails when a flat setting comes back false" {
  call_in_repo assert_applied delete_branch_on_merge false true
  [ "$status" -ne 0 ]
  [[ "$output" == *"is 'false', not 'true'"* ]]
}

# ─── apply_* read-back, with gh stubbed ────────────────────────────────────
#
# A shell function named gh shadows the real binary, so these exercise the
# apply path against a response of our choosing without touching the network.

@test "apply_security_settings rejects a success response that did not apply" {
  export STUB_REPO="{\"private\":false,$OWNER_ORG}"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { echo disabled; }
    apply_security_settings "$STUB_REPO"
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"secret_scanning"* ]]
  [[ "$output" == *"not 'enabled'"* ]]
}

@test "apply_security_settings accepts a response that reports the setting enabled" {
  export STUB_REPO="{\"private\":false,$OWNER_ORG}"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { echo enabled; }
    apply_security_settings "$STUB_REPO"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
}

@test "apply_security_settings writes non-provider patterns on an organization-owned repo" {
  export STUB_REPO="{\"private\":false,$OWNER_ORG}"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$*" >> "$CALLS"; echo enabled; }
    apply_security_settings "$STUB_REPO"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$(cat "$CALLS")" == *"secret_scanning_non_provider_patterns"* ]]
}

@test "apply_security_settings never writes non-provider patterns on a personal-account repo" {
  export STUB_REPO="{\"private\":false,$OWNER_USER}"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$*" >> "$CALLS"; echo enabled; }
    apply_security_settings "$STUB_REPO"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  # The other two still land; only the unsupported one is held back.
  [[ "$(cat "$CALLS")" == *"secret_scanning_push_protection"* ]]
  [[ "$(cat "$CALLS")" != *"secret_scanning_non_provider_patterns"* ]]
}

@test "apply_security_settings writes nothing on a private repo" {
  export STUB_REPO="{\"private\":true,$OWNER_ORG}"
  export CALLS="$BATS_TEST_TMPDIR/calls"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$*" >> "$CALLS"; echo enabled; }
    apply_security_settings "$STUB_REPO"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [ ! -s "$CALLS" ]
}

@test "apply_repo_settings rejects a success response that did not apply" {
  # Passed through the environment: an unquoted JSON literal inside the script
  # body would brace-expand before the stub ever ran.
  export STUB_RESPONSE='{"allow_auto_merge":true,"allow_update_branch":false,"delete_branch_on_merge":true}'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { echo "$STUB_RESPONSE"; }
    apply_repo_settings
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"allow_update_branch"* ]]
  [[ "$output" == *"not 'true'"* ]]
}

@test "apply_repo_settings accepts a response with every setting true" {
  export STUB_RESPONSE='{"allow_auto_merge":true,"allow_update_branch":true,"delete_branch_on_merge":true}'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { echo "$STUB_RESPONSE"; }
    apply_repo_settings
  ' _ "$BIN"
  [ "$status" -eq 0 ]
}

# ─── run_repo_settings_section, with gh stubbed ────────────────────────────

@test "run_repo_settings_section dry run names the non-provider skip and writes nothing" {
  export STUB_REPO="{$FLAT_OFF,\"private\":false,$OWNER_USER,$SA_OFF}"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=1
    gh() {
      for a in "$@"; do
        [ "$a" = "--method" ] && { echo "DRY RUN WROTE" >&2; return 0; }
      done
      printf "%s\n" "$STUB_REPO"
    }
    run_repo_settings_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (personal-account repo - needs an organization-owned repo)"* ]]
  [[ "$output" != *"DRY RUN WROTE"* ]]
}

@test "run_repo_settings_section dry run flags the non-provider change on an organization repo" {
  export STUB_REPO="{$FLAT_OFF,\"private\":false,$OWNER_ORG,$SA_OFF}"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=1
    gh() {
      for a in "$@"; do
        [ "$a" = "--method" ] && { echo "DRY RUN WROTE" >&2; return 0; }
      done
      printf "%s\n" "$STUB_REPO"
    }
    run_repo_settings_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  local line
  line="$(grep secret_scanning_non_provider_patterns <<< "$output")"
  [[ "$line" == *"disabled -> enabled (would change)"* ]]
  [[ "$output" != *"DRY RUN WROTE"* ]]
}

# ─── dependabot_state, with gh stubbed ─────────────────────────────────────
#
# The stub replays a whole `gh api -i` response - status line, headers, blank
# line, body - because dependabot_state parses the status line rather than
# trusting gh's exit code. STUB_RESPONSE travels through the environment and
# STUB_RC sets the exit code, since gh exits non-zero on the 404 that means
# "not enabled".

# stub_gh_state <exit code> <response>: run dependabot_state against a canned
# `gh api -i` response.
stub_gh_state() {
  export STUB_RC="$1" STUB_RESPONSE="$2"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$STUB_RESPONSE"; return "$STUB_RC"; }
    dependabot_state "$2"
  ' _ "$BIN" "$3"
}

@test "dependabot_state reads a 204 on vulnerability-alerts as enabled" {
  stub_gh_state 0 'HTTP/2.0 204 No Content' vulnerability-alerts
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]
}

@test "dependabot_state reads a 404 on vulnerability-alerts as disabled" {
  stub_gh_state 1 'HTTP/2.0 404 Not Found' vulnerability-alerts
  [ "$status" -eq 0 ]
  [ "$output" = "disabled" ]
}

@test "dependabot_state reads enabled=true on automated-security-fixes as enabled" {
  stub_gh_state 0 'HTTP/2.0 200 OK
Content-Type: application/json

{"enabled":true,"paused":false}' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]
}

# The live endpoint answers 200 with enabled=false rather than the 404 the docs
# describe, and false must not be folded into the unknown fallback.
@test "dependabot_state reads enabled=false on automated-security-fixes as disabled" {
  stub_gh_state 0 'HTTP/2.0 200 OK
Content-Type: application/json

{"enabled":false,"paused":false}' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "disabled" ]
}

@test "dependabot_state reads the documented 404 on automated-security-fixes as disabled" {
  stub_gh_state 1 'HTTP/2.0 404 Not Found' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "disabled" ]
}

@test "dependabot_state reports unknown rather than disabled on a server error" {
  stub_gh_state 1 'HTTP/2.0 500 Internal Server Error' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "dependabot_state reports unknown when gh produces no status line" {
  stub_gh_state 1 '' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "dependabot_state reports unknown when a 200 body has no enabled field" {
  stub_gh_state 0 'HTTP/2.0 200 OK

{"paused":false}' automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "unknown" ]
}

@test "dependabot_state tolerates CRLF header line endings" {
  stub_gh_state 0 "$(printf 'HTTP/2.0 200 OK\r\nContent-Type: application/json\r\n\r\n{"enabled":true}')" automated-security-fixes
  [ "$status" -eq 0 ]
  [ "$output" = "enabled" ]
}

# ─── dependabot_settings_diff, with gh stubbed ─────────────────────────────

@test "dependabot_settings_diff flags both settings when they are disabled" {
  export STUB_RESPONSE='HTTP/2.0 404 Not Found'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$STUB_RESPONSE"; return 1; }
    dependabot_settings_diff
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vulnerability-alerts:"* ]]
  [[ "$output" == *"automated-security-fixes:"* ]]
  [[ "$output" == *"disabled -> enabled (would change)"* ]]
}

@test "dependabot_settings_diff reports no change when both are enabled" {
  # 204 satisfies alerts; security updates fall through to the body check.
  export STUB_RESPONSE='HTTP/2.0 204 No Content'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$STUB_RESPONSE"; }
    dependabot_settings_diff
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled (no change)"* ]]
  [[ "$output" != *"would change"* ]]
}

@test "dependabot_settings_diff aligns its values with repo_settings_diff" {
  export STUB_RESPONSE='HTTP/2.0 404 Not Found'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$STUB_RESPONSE"; return 1; }
    repo_settings_diff "{\"allow_auto_merge\":true,\"allow_update_branch\":true,\"delete_branch_on_merge\":true,\"private\":false,\"security_and_analysis\":{\"secret_scanning\":{\"status\":\"enabled\"},\"secret_scanning_push_protection\":{\"status\":\"enabled\"}}}"
    dependabot_settings_diff
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  run bash -c 'awk "{ print index(\$0, \$2) }" <<< "$1" | sort -u | wc -l' _ "$output"
  [ "$output" -eq 1 ]
}

# ─── apply_dependabot_setting, with gh stubbed ─────────────────────────────

@test "apply_dependabot_setting dies when the PUT itself fails" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { return 1; }
    apply_dependabot_setting vulnerability-alerts "Dependabot alerts"
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to enable Dependabot alerts"* ]]
  [[ "$output" == *"owner/repo"* ]]
}

@test "apply_dependabot_setting rejects a PUT that reported success but did not apply" {
  # The PUT (no -i) succeeds silently; the read-back -i call reports a 404.
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() {
      for a in "$@"; do [ "$a" = "-i" ] && { echo "HTTP/2.0 404 Not Found"; return 1; }; done
      return 0
    }
    apply_dependabot_setting vulnerability-alerts "Dependabot alerts"
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"vulnerability-alerts"* ]]
  [[ "$output" == *"is 'disabled', not 'enabled'"* ]]
}

@test "apply_dependabot_setting accepts a PUT the read-back confirms" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() {
      for a in "$@"; do [ "$a" = "-i" ] && { echo "HTTP/2.0 204 No Content"; return 0; }; done
      return 0
    }
    apply_dependabot_setting vulnerability-alerts "Dependabot alerts"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
}

# ─── run_dependabot_section ────────────────────────────────────────────────

@test "run_dependabot_section dry run diffs both settings and makes no changes" {
  export STUB_RESPONSE='HTTP/2.0 404 Not Found'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=1
    gh() {
      for a in "$@"; do
        [ "$a" = "--method" ] && { echo "DRY RUN WROTE" >&2; return 0; }
      done
      printf "%s\n" "$STUB_RESPONSE"; return 1
    }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"vulnerability-alerts:"* ]]
  [[ "$output" == *"automated-security-fixes:"* ]]
  [[ "$output" == *"would change"* ]]
  [[ "$output" != *"DRY RUN WROTE"* ]]
}

@test "run_dependabot_section dry run notes that malware alerts need the UI" {
  export STUB_RESPONSE='HTTP/2.0 404 Not Found'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=1
    gh() { printf "%s\n" "$STUB_RESPONSE"; return 1; }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"malware alerts"* ]]
  [[ "$output" == *"Settings UI"* ]]
}

@test "run_dependabot_section leaves already-enabled settings alone without prompting" {
  export STUB_RESPONSE='HTTP/2.0 204 No Content'
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=""
    confirm() { echo "PROMPTED" >&2; return 0; }
    gh() {
      for a in "$@"; do
        [ "$a" = "--method" ] && { echo "WROTE" >&2; return 0; }
      done
      printf "%s\n" "$STUB_RESPONSE"
    }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"already enabled"* ]]
  [[ "$output" != *"PROMPTED"* ]]
  [[ "$output" != *"WROTE"* ]]
}

@test "run_dependabot_section offers each disabled setting its own confirmation" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=""
    confirm() { echo "PROMPT: $1"; return 1; }
    gh() { echo "HTTP/2.0 404 Not Found"; return 1; }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROMPT: Dependabot alerts"* ]]
  [[ "$output" == *"PROMPT: Dependabot security updates"* ]]
}

@test "run_dependabot_section writes nothing when both confirmations are declined" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=""
    confirm() { return 1; }
    gh() {
      for a in "$@"; do
        [ "$a" = "--method" ] && { echo "WROTE" >&2; return 0; }
      done
      echo "HTTP/2.0 404 Not Found"; return 1
    }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped."* ]]
  [[ "$output" != *"WROTE"* ]]
}

@test "run_dependabot_section enables each confirmed setting and prints the malware note" {
  STUB_DIR="$(mktemp -d)"
  export STUB_DIR
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN=""
    confirm() { return 0; }
    # Each endpoint reads 404 until its own PUT lands and 204 afterwards, so the
    # read-back confirms the write it belongs to rather than a sibling setting.
    gh() {
      local path="${@: -1}" flag put=""
      for a in "$@"; do [ "$a" = "--method" ] && put=1; done
      flag="$STUB_DIR/$(basename "$path")"
      if [ -n "$put" ]; then touch "$flag"; return 0; fi
      if [ -e "$flag" ]; then echo "HTTP/2.0 204 No Content"; return 0; fi
      echo "HTTP/2.0 404 Not Found"; return 1
    }
    run_dependabot_section
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"enabled Dependabot alerts."* ]]
  [[ "$output" == *"enabled Dependabot security updates."* ]]
  [[ "$output" == *"malware alerts are npm-only"* ]]
}

# ─── plane_config_value (pure) ─────────────────────────────────────────────

# plane_yml <lines...>: write a .workitems.plane.yml fixture and print its path.
plane_yml() {
  local file="$BATS_TEST_TMPDIR/plane-$$.yml"
  printf '%s\n' "$@" > "$file"
  printf '%s\n' "$file"
}

@test "plane_config_value reads an unquoted scalar" {
  call plane_config_value "$(plane_yml 'project: DX')" project
  [ "$status" -eq 0 ]
  [ "$output" = "DX" ]
}

@test "plane_config_value strips surrounding quotes of either kind" {
  call plane_config_value "$(plane_yml 'project: "DX"' "workspace: 'acme'")" workspace
  [ "$status" -eq 0 ]
  [ "$output" = "acme" ]
}

@test "plane_config_value strips a trailing inline comment" {
  call plane_config_value "$(plane_yml 'workspace: acme  # the only one')" workspace
  [ "$status" -eq 0 ]
  [ "$output" = "acme" ]
}

@test "plane_config_value reads a commented-out key as absent" {
  call plane_config_value "$(plane_yml 'project: DX' '# workspace: acme')" workspace
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plane_config_value ignores an indented key of the same name" {
  # `project` nested under another key is not a repo-level default, and reading
  # it as one would build an autolink for the wrong prefix.
  call plane_config_value "$(plane_yml 'modules:' '  project: NESTED')" project
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── plane_config_path (needs a checkout) ──────────────────────────────────

# checkout_with_origin <origin-url> [plane.yml lines...]: build a temp repo,
# cd into it, and print its path.
checkout_with_origin() {
  local origin="$1"; shift
  local dir="$BATS_TEST_TMPDIR/checkout"
  mkdir -p "$dir"
  git -C "$dir" init --quiet
  git -C "$dir" remote add origin "$origin"
  [[ $# -eq 0 ]] || printf '%s\n' "$@" > "$dir/.workitems.plane.yml"
  printf '%s\n' "$dir"
}

@test "plane_config_path finds the root .workitems.plane.yml when the origin matches" {
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git' 'project: DX')"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    cd "$2" || exit 1
    plane_config_path
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.workitems.plane.yml" ]]
}

@test "plane_config_path finds the pre-rename .plane.yml when asked for it" {
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git')"
  printf 'project: DX\n' > "$dir/.plane.yml"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    cd "$2" || exit 1
    plane_config_path .plane.yml
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/.plane.yml" ]]
}

@test "plane_config_path does not fall back to .plane.yml on its own" {
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git')"
  printf 'project: DX\n' > "$dir/.plane.yml"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    cd "$2" || exit 1
    plane_config_path
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plane_config_path finds nothing when the checkout is a different repo" {
  # The guard that stops a run from one repo stamping another repo's prefix.
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git' 'project: DX')"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=someone/else
    cd "$2" || exit 1
    plane_config_path
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "plane_config_path prefers the root .workitems.plane.yml over tmp/" {
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git' 'project: DX')"
  mkdir -p "$dir/tmp"
  printf 'project: ZZ\n' > "$dir/tmp/.workitems.plane.yml"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    cd "$2" || exit 1
    plane_config_path
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" != *"/tmp/.workitems.plane.yml" ]]
}

@test "plane_config_path falls back to tmp/.workitems.plane.yml" {
  local dir; dir="$(checkout_with_origin 'git@github.com:owner/repo.git')"
  mkdir -p "$dir/tmp"
  printf 'project: DX\n' > "$dir/tmp/.workitems.plane.yml"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    cd "$2" || exit 1
    plane_config_path
  ' _ "$BIN" "$dir"
  [ "$status" -eq 0 ]
  [[ "$output" == *"/tmp/.workitems.plane.yml" ]]
}

# ─── autolink_desired, with plane_config_path stubbed ──────────────────────

# desired_from <plane.yml lines...>: run autolink_desired against a fixture.
desired_from() {
  export STUB_CONFIG; STUB_CONFIG="$(plane_yml "$@")"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    plane_config_path() { printf "%s\n" "$STUB_CONFIG"; }
    autolink_desired
  ' _ "$BIN"
}

@test "autolink_desired builds the prefix and template from project and workspace" {
  desired_from 'project: DX' 'workspace: acme'
  [ "$status" -eq 0 ]
  [ "$output" = 'DX-|https://app.plane.so/acme/browse/DX-<num>/' ]
}

@test "autolink_desired uppercases a lowercase project identifier" {
  desired_from 'project: dx' 'workspace: acme'
  [ "$status" -eq 0 ]
  [ "$output" = 'DX-|https://app.plane.so/acme/browse/DX-<num>/' ]
}

@test "autolink_desired refuses a project that is a display name" {
  # A name builds an autolink matching nothing anyone writes - configured but inert.
  desired_from 'project: Developer Experience' 'workspace: acme'
  [ "$status" -eq 0 ]
  [[ "$output" == '!project "Developer Experience" is a name'* ]]
}

@test "autolink_desired reports a missing workspace rather than guessing one" {
  desired_from 'project: DX' '# workspace: acme'
  [ "$status" -eq 0 ]
  [[ "$output" == '!'*"sets no workspace" ]]
}

@test "autolink_desired reports a missing project" {
  desired_from 'workspace: acme'
  [ "$status" -eq 0 ]
  [[ "$output" == '!'*"sets no project" ]]
}

@test "autolink_desired reports the absence of a config file" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    plane_config_path() { return 0; }
    autolink_desired
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == '!no .workitems.plane.yml'* ]]
}

@test "autolink_desired names the migration when only a pre-rename config exists" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    plane_config_path() { [[ "${1:-}" == ".plane.yml" ]] && printf "/repo/.plane.yml\n"; return 0; }
    autolink_desired
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == '!/repo/.plane.yml predates'* ]]
  [[ "$output" == *"migrate-work-item-config"* ]]
}

# ─── autolink_state, with gh stubbed ───────────────────────────────────────

# stub_autolinks <json array>: run autolink_state against a canned list.
stub_autolinks() {
  export STUB_RESPONSE="$1"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$STUB_RESPONSE"; }
    autolink_state "DX-" "https://app.plane.so/acme/browse/DX-<num>/"
  ' _ "$BIN"
}

@test "autolink_state reports absent when the repo has no autolinks" {
  stub_autolinks '[]'
  [ "$status" -eq 0 ]
  [ "$output" = "absent" ]
}

@test "autolink_state reports absent when another prefix is configured" {
  stub_autolinks '[{"id":1,"key_prefix":"JIRA-","url_template":"https://example.com/<num>"}]'
  [ "$status" -eq 0 ]
  [ "$output" = "absent" ]
}

@test "autolink_state reports match on an identical template" {
  stub_autolinks '[{"id":1,"key_prefix":"DX-","url_template":"https://app.plane.so/acme/browse/DX-<num>/"}]'
  [ "$status" -eq 0 ]
  [ "$output" = "match" ]
}

@test "autolink_state reports mismatch and carries the current template" {
  stub_autolinks '[{"id":1,"key_prefix":"DX-","url_template":"https://app.plane.so/old/browse/DX-<num>/"}]'
  [ "$status" -eq 0 ]
  [ "$output" = "mismatch https://app.plane.so/old/browse/DX-<num>/" ]
}

# ─── apply_autolink, with gh stubbed ───────────────────────────────────────

@test "apply_autolink posts the prefix, template and a numeric identifier" {
  # The stub reports on stderr because apply_autolink sends gh's stdout to
  # /dev/null; there is no response worth reading from either write.
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$*" >&2; }
    apply_autolink "DX-" "https://app.plane.so/acme/browse/DX-<num>/"
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"--method POST /repos/owner/repo/autolinks"* ]]
  [[ "$output" == *"key_prefix=DX-"* ]]
  [[ "$output" == *"url_template=https://app.plane.so/acme/browse/DX-<num>/"* ]]
  # Plane suffixes are always integers; the API would otherwise default this to
  # true and also match DX-49a.
  [[ "$output" == *"is_alphanumeric=false"* ]]
}

@test "apply_autolink deletes the existing entry before recreating it" {
  # GitHub has no update endpoint for autolinks, so a replacement is two calls
  # and the delete has to come first.
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { printf "%s\n" "$*" >&2; }
    apply_autolink "DX-" "https://app.plane.so/acme/browse/DX-<num>/" 7
  ' _ "$BIN"
  [ "$status" -eq 0 ]
  [[ "${lines[0]}" == *"--method DELETE /repos/owner/repo/autolinks/7"* ]]
  [[ "${lines[1]}" == *"--method POST /repos/owner/repo/autolinks"* ]]
}

@test "apply_autolink dies when the POST fails" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { return 1; }
    apply_autolink "DX-" "https://app.plane.so/acme/browse/DX-<num>/"
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to create the DX- autolink"* ]]
  [[ "$output" == *"owner/repo"* ]]
}

@test "apply_autolink dies when the delete half of a replacement fails" {
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    gh() { return 1; }
    apply_autolink "DX-" "https://app.plane.so/acme/browse/DX-<num>/" 7
  ' _ "$BIN"
  [ "$status" -ne 0 ]
  [[ "$output" == *"failed to remove the existing DX- autolink"* ]]
}

# ─── run_autolink_section ──────────────────────────────────────────────────

# section_with <desired> <state> [dry-run] [confirm rc]: run the section with
# both lookups stubbed, so no test depends on a checkout or the network.
section_with() {
  export STUB_DESIRED="$1" STUB_STATE="$2" STUB_DRY="${3:-}" STUB_CONFIRM="${4:-1}"
  run bash -c '
    _GH_SETTINGS_LIB_ONLY=1 source "$1"
    OWNER_REPO=owner/repo
    DRY_RUN="$STUB_DRY"
    autolink_desired() { printf "%s\n" "$STUB_DESIRED"; }
    autolink_state() { printf "%s\n" "$STUB_STATE"; }
    autolink_lookup() { printf "7\n"; }
    confirm() { return "$STUB_CONFIRM"; }
    apply_autolink() { printf "APPLIED %s\n" "$*"; }
    run_autolink_section
  ' _ "$BIN"
}

@test "run_autolink_section reports the skip reason it was given" {
  section_with '!/repo/.workitems.plane.yml sets no workspace' absent
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped (/repo/.workitems.plane.yml sets no workspace)"* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section dry run shows the create without making it" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' absent 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"would change"* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section dry run reports no change on a match" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' match 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"no change"* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section dry run flags a replacement" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' 'mismatch https://old/<num>' 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"would replace"* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section leaves a matching autolink alone without prompting" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' match
  [ "$status" -eq 0 ]
  [[ "$output" == *"already configured"* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section creates a confirmed autolink" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' absent '' 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"APPLIED DX- https://app.plane.so/acme/browse/DX-<num>/"* ]]
  [[ "$output" == *"created the DX- autolink"* ]]
}

@test "run_autolink_section writes nothing when the confirmation is declined" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' absent '' 1
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped."* ]]
  [[ "$output" != *"APPLIED"* ]]
}

@test "run_autolink_section passes the existing id when replacing" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' 'mismatch https://old/<num>' '' 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"currently points at https://old/<num>"* ]]
  [[ "$output" == *"APPLIED DX- https://app.plane.so/acme/browse/DX-<num>/ 7"* ]]
}

@test "run_autolink_section notes that titles are not autolinked" {
  # The one caveat worth surfacing at the point the autolink is created.
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' absent '' 0
  [ "$status" -eq 0 ]
  [[ "$output" == *"not in PR or issue titles"* ]]
}

@test "run_autolink_section keeps the titles note off a declined run" {
  section_with 'DX-|https://app.plane.so/acme/browse/DX-<num>/' absent '' 1
  [ "$status" -eq 0 ]
  [[ "$output" != *"not in PR or issue titles"* ]]
}
