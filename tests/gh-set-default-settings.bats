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
