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
SA_ON='"security_and_analysis":{"secret_scanning":{"status":"enabled"},"secret_scanning_push_protection":{"status":"enabled"}}'
SA_OFF='"security_and_analysis":{"secret_scanning":{"status":"disabled"},"secret_scanning_push_protection":{"status":"disabled"}}'

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
  local cur="{$FLAT_ON,\"private\":false,$SA_OFF}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning:"* ]]
  [[ "$output" == *"secret_scanning_push_protection:"* ]]
  [[ "$output" == *"disabled -> enabled (would change)"* ]]
}

@test "repo_settings_diff reports no change when security settings are already enabled" {
  local cur="{$FLAT_ON,\"private\":false,$SA_ON}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  [[ "$output" == *"secret_scanning:"* ]]
  [[ "$output" == *"enabled (no change)"* ]]
  [[ "$output" != *"would change"* ]]
}

@test "repo_settings_diff treats an absent security_and_analysis as a change" {
  local cur="{$FLAT_ON,\"private\":false,\"security_and_analysis\":null}"
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
  local cur="{$FLAT_ON,\"private\":false,$SA_ON}"
  call repo_settings_diff "$cur"
  [ "$status" -eq 0 ]
  # Every line pads the label to the same column, so the values line up.
  run bash -c 'awk "{ print index(\$0, \$2) }" <<< "$1" | sort -u | wc -l' _ "$output"
  [ "$output" -eq 1 ]
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
