#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

BIN="$DOTFILES_ROOT/bin/git-set-default-settings"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_GIT_SETTINGS_LIB_ONLY=1 source "$0"; "$@"' "$BIN" "$@"
}

# ─── flags & help ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: git-set-default-settings"* ]]
}

@test "an unknown flag exits non-zero" {
  run "$BIN" --nope
  [ "$status" -ne 0 ]
}

@test "a second positional path argument exits non-zero" {
  run "$BIN" . /tmp
  [ "$status" -ne 0 ]
}

@test "a path that is not a git repo exits non-zero" {
  local dir
  dir="$(mktemp -d)"
  run "$BIN" --dry-run "$dir"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not a git repository"* ]]
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

# ─── plan_has (pure) ───────────────────────────────────────────────────────

@test "plan_has finds a change line" {
  call plan_has "$(printf 'ok:      fine\nchange:  do a thing\n')" change
  [ "$status" -eq 0 ]
}

@test "plan_has reports absence when every line is ok" {
  call plan_has "$(printf 'ok:      fine\nok:      also fine\n')" change
  [ "$status" -ne 0 ]
}

@test "plan_has finds a blocked line" {
  call plan_has "$(printf 'change:  do a thing\nblocked: cannot\n')" blocked
  [ "$status" -eq 0 ]
}

@test "plan_has does not match a prefix in the middle of a line" {
  call plan_has "$(printf 'ok:      mentions change: inline\n')" change
  [ "$status" -ne 0 ]
}

# ─── fixtures ──────────────────────────────────────────────────────────────

# new_repo: print the path to a fresh git repo with one commit.
new_repo() {
  local d
  d="$(mktemp -d)"
  git init -q -b main "$d"
  echo readme > "$d/README.md"
  git -C "$d" add README.md
  git -C "$d" commit -qm "first"
  printf '%s\n' "$d"
}

# ─── gitleaks_precommit_plan ───────────────────────────────────────────────

@test "gitleaks plan reports changes for a fresh repo" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"change:"* ]]
  [[ "$output" == *"gitleaks"* ]]
}

@test "gitleaks plan reports the pre-push hook as a separate change" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_plan "$repo"
  [[ "$output" == *"pre-push"* ]]
}

@test "gitleaks plan reports no change after apply" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  [ "$status" -eq 0 ]
  call gitleaks_precommit_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"change:"* ]]
}

@test "gitleaks apply is idempotent - a second apply changes nothing" {
  local repo before after
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  before="$(cat "$repo/.pre-commit-config.yaml")"
  call gitleaks_precommit_apply "$repo"
  [ "$status" -eq 0 ]
  after="$(cat "$repo/.pre-commit-config.yaml")"
  [ "$before" = "$after" ]
}

@test "gitleaks apply preserves unrelated hooks in an existing config" {
  local repo
  repo="$(new_repo)"
  cat > "$repo/.pre-commit-config.yaml" <<'YAML'
repos:
  - repo: local
    hooks:
      - id: my-own-hook
        name: my own hook
        entry: echo hi
        language: system
YAML
  call gitleaks_precommit_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"my-own-hook"* ]]
  [[ "$output" == *"gitleaks"* ]]
}

@test "gitleaks apply pins the published hook to a rev" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"github.com/gitleaks/gitleaks"* ]]
  [[ "$output" == *"rev:"* ]]
}

@test "gitleaks apply scopes the history hook to unpushed commits on pre-push" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"HEAD --not --remotes"* ]]
  [[ "$output" == *"pre-push"* ]]
}

@test "gitleaks apply installs both git hook types" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  [ -f "$repo/.git/hooks/pre-commit" ]
  [ -f "$repo/.git/hooks/pre-push" ]
}

# ─── gitleaks-history hook, end to end ─────────────────────────────────────
#
# Exercises the real hook through pre-commit, which shlex-splits `entry`. These
# assert the scan scope actually lands: --log-opts must survive quoting, and the
# range must be the unpushed commits rather than all of history.

@test "the history hook catches a secret in an unpushed commit" {
  local repo up
  repo="$(new_repo)"
  up="$(mktemp -d)"
  git init -q --bare "$up"
  git -C "$repo" remote add origin "$up"
  git -C "$repo" push -q -u origin main
  call gitleaks_precommit_apply "$repo"

  # A fixture secret, deliberately detectable so the hook under test fires.
  printf 'aws_key = "AKIAIMNOJVGFDXXXE4OA"\n' > "$repo/creds.txt"  # gitleaks:allow
  git -C "$repo" add creds.txt
  # --no-verify: the staged tier would block this commit, which is the point of
  # that tier. This scenario is setting up the pre-push tier instead.
  git -C "$repo" commit -qm "add creds" --no-verify

  run bash -c 'cd "$1" && pre-commit run --hook-stage pre-push gitleaks-history' _ "$repo"
  [ "$status" -ne 0 ]
}

@test "the history hook passes when every commit is already pushed" {
  local repo up
  repo="$(new_repo)"
  up="$(mktemp -d)"
  git init -q --bare "$up"
  git -C "$repo" remote add origin "$up"
  git -C "$repo" push -q -u origin main
  call gitleaks_precommit_apply "$repo"

  run bash -c 'cd "$1" && pre-commit run --hook-stage pre-push gitleaks-history' _ "$repo"
  [ "$status" -eq 0 ]
}

@test "the history hook scans everything when the repo has no remote" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"

  # A fixture secret, deliberately detectable so the hook under test fires.
  printf 'aws_key = "AKIAIMNOJVGFDXXXE4OA"\n' > "$repo/creds.txt"  # gitleaks:allow
  git -C "$repo" add creds.txt
  # --no-verify: the staged tier would block this commit, which is the point of
  # that tier. This scenario is setting up the pre-push tier instead.
  git -C "$repo" commit -qm "add creds" --no-verify

  run bash -c 'cd "$1" && pre-commit run --hook-stage pre-push gitleaks-history' _ "$repo"
  [ "$status" -ne 0 ]
}

@test "gitleaks plan blocks on a foreign pre-commit hook" {
  local repo
  repo="$(new_repo)"
  printf '#!/bin/sh\necho mine\n' > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
  call gitleaks_precommit_plan "$repo"
  [[ "$output" == *"blocked:"* ]]
}

# ─── dependabot_precommit ──────────────────────────────────────────────────
#
# ASSIGNEE is read from the environment: main() fills it from `gh api user`, so
# leaving it unset here keeps these tests off the network.

@test "dependabot plan reports a change for a repo with no config" {
  local repo
  repo="$(new_repo)"
  call dependabot_precommit_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"change:"* ]]
}

@test "dependabot plan reports no change after apply" {
  local repo
  repo="$(new_repo)"
  call dependabot_precommit_apply "$repo"
  [ "$status" -eq 0 ]
  call dependabot_precommit_plan "$repo"
  [[ "$output" != *"change:"* ]]
}

@test "dependabot apply declares the pre-commit ecosystem" {
  local repo
  repo="$(new_repo)"
  call dependabot_precommit_apply "$repo"
  run cat "$repo/.github/dependabot.yml"
  [[ "$output" == *"package-ecosystem: pre-commit"* ]]
  [[ "$output" == *"version: 2"* ]]
}

@test "dependabot apply is idempotent - a second apply changes nothing" {
  local repo before after
  repo="$(new_repo)"
  call dependabot_precommit_apply "$repo"
  before="$(cat "$repo/.github/dependabot.yml")"
  call dependabot_precommit_apply "$repo"
  after="$(cat "$repo/.github/dependabot.yml")"
  [ "$before" = "$after" ]
}

@test "dependabot apply preserves an existing ecosystem block" {
  local repo
  repo="$(new_repo)"
  mkdir -p "$repo/.github"
  cat > "$repo/.github/dependabot.yml" <<'YAML'
version: 2
updates:
  - package-ecosystem: github-actions
    directory: /
    schedule:
      interval: weekly
YAML
  call dependabot_precommit_apply "$repo"
  run cat "$repo/.github/dependabot.yml"
  [[ "$output" == *"github-actions"* ]]
  [[ "$output" == *"pre-commit"* ]]
}

@test "dependabot apply sets the assignee when one is known" {
  local repo
  repo="$(new_repo)"
  ASSIGNEE=octocat call dependabot_precommit_apply "$repo"
  run cat "$repo/.github/dependabot.yml"
  [[ "$output" == *"assignees:"* ]]
  [[ "$output" == *"octocat"* ]]
}

@test "dependabot apply omits assignees when none is known" {
  local repo
  repo="$(new_repo)"
  call dependabot_precommit_apply "$repo"
  run cat "$repo/.github/dependabot.yml"
  [[ "$output" == *"package-ecosystem: pre-commit"* ]]
  [[ "$output" != *"assignees:"* ]]
}

# ─── driver, end to end ────────────────────────────────────────────────────

@test "--dry-run lists both settings" {
  local repo
  repo="$(new_repo)"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitleaks secret scanning"* ]]
  [[ "$output" == *"Dependabot updates for pre-commit hooks"* ]]
  [[ "$output" == *"change:"* ]]
}

@test "--dry-run changes nothing on disk" {
  local repo
  repo="$(new_repo)"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [ ! -e "$repo/.pre-commit-config.yaml" ]
  [ ! -e "$repo/.github/dependabot.yml" ]
  [ ! -e "$repo/.git/hooks/pre-push" ]
}

@test "--dry-run reports nothing to do against a configured repo" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  call dependabot_precommit_apply "$repo"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"change:"* ]]
  [[ "$output" == *"nothing to do"* ]]
}

@test "--dry-run surfaces a blocked hook without applying" {
  local repo
  repo="$(new_repo)"
  printf '#!/bin/sh\necho mine\n' > "$repo/.git/hooks/pre-commit"
  chmod +x "$repo/.git/hooks/pre-commit"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"blocked:"* ]]
  [ ! -e "$repo/.pre-commit-config.yaml" ]
}

@test "--dry-run defaults to the current directory" {
  local repo
  repo="$(new_repo)"
  run bash -c 'cd "$1" && "$2" --dry-run' _ "$repo" "$BIN"
  [ "$status" -eq 0 ]
  [[ "$output" == *"gitleaks"* ]]
}

@test "a missing required tool exits non-zero with a clear message" {
  local repo
  repo="$(new_repo)"
  PATH=/usr/bin:/bin run "$BIN" --dry-run "$repo"
  [ "$status" -ne 0 ]
  [[ "$output" == *"not found on PATH"* ]]
}

# Regression coverage rather than a TDD cycle: the generated config already
# validates. It asserts the wiring stays acceptable to pre-commit itself, which
# the string assertions above cannot catch.
@test "the generated config is valid per pre-commit" {
  local repo
  repo="$(new_repo)"
  call gitleaks_precommit_apply "$repo"
  run bash -c 'cd "$1" && pre-commit validate-config .pre-commit-config.yaml' _ "$repo"
  [ "$status" -eq 0 ]
}
