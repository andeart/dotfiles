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

# ─── plan_is_pending / ask line parsing (pure) ─────────────────────────────

@test "plan_is_pending treats a change line as pending work" {
  call plan_is_pending "$(printf 'ok:      fine\nchange:  do a thing\n')"
  [ "$status" -eq 0 ]
}

@test "plan_is_pending treats an ask line as pending work" {
  call plan_is_pending "$(printf 'ok:      fine\nask:     a_key|do a thing?\n')"
  [ "$status" -eq 0 ]
}

@test "plan_is_pending reports nothing pending when every line is ok" {
  call plan_is_pending "$(printf 'ok:      fine\nok:      also fine\n')"
  [ "$status" -ne 0 ]
}

@test "ask_key extracts the key from an ask line" {
  call ask_key "ask:     widen_hook_types|add pre-push to it?"
  [ "$status" -eq 0 ]
  [ "$output" = "widen_hook_types" ]
}

@test "ask_message extracts the question from an ask line" {
  call ask_message "ask:     widen_hook_types|add pre-push to it?"
  [ "$status" -eq 0 ]
  [ "$output" = "add pre-push to it?" ]
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

# ─── precommit_base ────────────────────────────────────────────────────────

@test "precommit base plan reports both defaults as changes for a fresh repo" {
  local repo
  repo="$(new_repo)"
  call precommit_base_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"change:"* ]]
  [[ "$output" == *"default_stages"* ]]
  [[ "$output" == *"default_install_hook_types"* ]]
}

@test "precommit base apply writes both defaults" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"default_stages: [pre-commit]"* ]]
  [[ "$output" == *"default_install_hook_types: [pre-commit, pre-push]"* ]]
}

@test "precommit base apply alone produces a config valid per pre-commit" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  run bash -c 'cd "$1" && pre-commit validate-config .pre-commit-config.yaml' _ "$repo"
  [ "$status" -eq 0 ]
}

@test "precommit base apply orders the defaults above repos in a new config" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  run grep -n -e '^default_stages' -e '^default_install_hook_types' -e '^repos' \
    "$repo/.pre-commit-config.yaml"
  [[ "${lines[0]}" == 1:default_stages* ]]
  [[ "${lines[1]}" == 2:default_install_hook_types* ]]
  [[ "${lines[2]}" == 3:repos* ]]
}

@test "precommit base plan reports no change after apply" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  call precommit_base_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"change:"* ]]
}

@test "precommit base apply is idempotent - a second apply changes nothing" {
  local repo before after
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  before="$(cat "$repo/.pre-commit-config.yaml")"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  after="$(cat "$repo/.pre-commit-config.yaml")"
  [ "$before" = "$after" ]
}

@test "precommit base apply preserves an existing config's repos" {
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
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"my-own-hook"* ]]
  [[ "$output" == *"default_stages"* ]]
}

@test "precommit base leaves an existing default_stages untouched" {
  local repo
  repo="$(new_repo)"
  printf 'default_stages: [pre-commit, pre-push]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  call precommit_base_plan "$repo"
  [[ "$output" == *"ok:"*"default_stages"* ]]
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"default_stages: [pre-commit, pre-push]"* ]]
}

# ─── precommit_base, widening an existing default_install_hook_types ────────
#
# Adding a hook type only causes more to be installed, so unlike default_stages
# it narrows nothing - but it still edits a value the consumer chose, which is
# why it is an "ask:" (its own prompt) rather than a plain "change:".

@test "precommit base plan asks before widening default_install_hook_types" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  call precommit_base_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ask:"*"widen_hook_types|"* ]]
  [[ "$output" == *"pre-push"* ]]
}

@test "precommit base plan does not ask when default_install_hook_types covers pre-push" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [pre-push, pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  call precommit_base_plan "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"ask:"* ]]
}

@test "precommit base apply leaves default_install_hook_types alone when the ask is declined" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"default_install_hook_types: [pre-commit]"* ]]
  [[ "$output" != *"pre-push"* ]]
}

@test "precommit base apply widens default_install_hook_types when the ask is accepted" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  ACCEPTED_ASKS=widen_hook_types call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"pre-commit"* ]]
  [[ "$output" == *"pre-push"* ]]
}

@test "precommit base apply preserves other entries when widening" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [commit-msg, pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  ACCEPTED_ASKS=widen_hook_types call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"commit-msg"* ]]
  [[ "$output" == *"pre-push"* ]]
}

# ─── driver prompt sequencing ──────────────────────────────────────────────
#
# prompt_yes_no reads /dev/tty, which a test run has no reliable handle on, so
# these stub it and feed answers in prompt order. What is under test is the
# driver's branching, not the three lines that read the terminal.

# drive <answers> <setting> <repo>: run one setting through the driver with the
# prompt stubbed. <answers> is a space-separated y/n list, consumed in order;
# anything past its end answers no. Each prompt is echoed as "PROMPT: <text>".
drive() {
  local answers="$1"; shift
  ANSWER_LIST="$answers" run bash -c '
    _GIT_SETTINGS_LIB_ONLY=1 source "$0"
    read -r -a ANSWERS <<<"$ANSWER_LIST"
    ANSWER_I=0
    prompt_yes_no() {
      printf "PROMPT: %s\n" "$1"
      local a="${ANSWERS[$ANSWER_I]:-n}"
      ANSWER_I=$((ANSWER_I + 1))
      reply_is_yes "$a"
    }
    DRY_RUN=""
    REPO="$2"
    run_setting "$1"
  ' "$BIN" "$@"
}

@test "the driver applies a widening the user accepts" {
  local repo
  repo="$(new_repo)"
  printf 'default_stages: [pre-commit]\ndefault_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  drive "y" precommit_base "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied."* ]]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"pre-push"* ]]
}

@test "the driver leaves a widening the user declines" {
  local repo
  repo="$(new_repo)"
  printf 'default_stages: [pre-commit]\ndefault_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  drive "n" precommit_base "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"skipped."* ]]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" != *"pre-push"* ]]
}

@test "declining a setting does not go on to ask its follow-up questions" {
  local repo
  repo="$(new_repo)"
  # default_stages absent (a change) and a narrow hook types list (an ask).
  printf 'default_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  drive "n y" precommit_base "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"PROMPT: Apply pre-commit base configuration?"* ]]
  # The ask is still listed in the plan; what must not happen is being asked it.
  [[ "$output" != *"PROMPT: default_install_hook_types"* ]]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" != *"default_stages"* ]]
  [[ "$output" != *"pre-push"* ]]
}

@test "accepting a setting but declining its ask applies only the changes" {
  local repo
  repo="$(new_repo)"
  printf 'default_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  drive "y n" precommit_base "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"applied."* ]]
  run cat "$repo/.pre-commit-config.yaml"
  [[ "$output" == *"default_stages"* ]]
  [[ "$output" != *"pre-push"* ]]
}

# ─── precommit_base, end to end ────────────────────────────────────────────
#
# Exercises the written keys through pre-commit itself. Each pair runs the same
# scenario with and without the setting applied, so the passing half cannot be
# passing on pre-commit's own defaults.

# add_stage_probe_hooks <repo>: append two local hooks - one declaring no stages
# (so its stage comes from default_stages) and one pinned to pre-push.
add_stage_probe_hooks() {
  yq -i '.repos += [{"repo": "local", "hooks": [
    {"id": "commit-probe", "name": "commit probe", "entry": "true",
     "language": "system", "pass_filenames": false, "always_run": true},
    {"id": "push-probe", "name": "push probe", "entry": "true",
     "language": "system", "pass_filenames": false, "always_run": true,
     "stages": ["pre-push"]}
  ]}]' "$1/.pre-commit-config.yaml"
}

@test "without the base setting a commit-stage hook also runs on push" {
  local repo
  repo="$(new_repo)"
  printf 'repos: []\n' > "$repo/.pre-commit-config.yaml"
  add_stage_probe_hooks "$repo"
  run bash -c 'cd "$1" && pre-commit run --hook-stage pre-push --all-files' _ "$repo"
  [[ "$output" == *"commit probe"* ]]
  [[ "$output" == *"push probe"* ]]
}

@test "a configured repo runs only its push-stage hooks on push" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  add_stage_probe_hooks "$repo"
  run bash -c 'cd "$1" && pre-commit run --hook-stage pre-push --all-files' _ "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"push probe"* ]]
  [[ "$output" != *"commit probe"* ]]
}

# The pair above resolves stages through `pre-commit run --hook-stage`. This one
# goes through a real `git push`, so it also covers the installed hook wiring.
@test "a real push runs only the push-stage hooks in a configured repo" {
  local repo up
  repo="$(new_repo)"
  up="$(mktemp -d)"
  git init -q --bare "$up"
  git -C "$repo" remote add origin "$up"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  call gitleaks_precommit_apply "$repo"
  [ "$status" -eq 0 ]
  # Fails hard if it is ever reached, so a push that survives proves it did not
  # run at the push stage.
  yq -i '.repos += [{"repo": "local", "hooks": [{"id": "commit-probe",
    "name": "commit probe", "entry": "false", "language": "system",
    "pass_filenames": false, "always_run": true}]}]' "$repo/.pre-commit-config.yaml"
  git -C "$repo" add -A
  git -C "$repo" commit -qm "probe" --no-verify

  run git -C "$repo" push -u origin main
  [ "$status" -eq 0 ]
  [[ "$output" != *"commit-probe"* ]]
}

@test "without the base setting a bare pre-commit install skips the push tier" {
  local repo
  repo="$(new_repo)"
  printf 'repos: []\n' > "$repo/.pre-commit-config.yaml"
  run bash -c 'cd "$1" && pre-commit install' _ "$repo"
  [ "$status" -eq 0 ]
  [ -f "$repo/.git/hooks/pre-commit" ]
  [ ! -f "$repo/.git/hooks/pre-push" ]
}

@test "a bare pre-commit install covers both hook types in a configured repo" {
  local repo
  repo="$(new_repo)"
  call precommit_base_apply "$repo"
  [ "$status" -eq 0 ]
  run bash -c 'cd "$1" && pre-commit install' _ "$repo"
  [ "$status" -eq 0 ]
  [ -f "$repo/.git/hooks/pre-commit" ]
  [ -f "$repo/.git/hooks/pre-push" ]
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

@test "--dry-run lists every setting" {
  local repo
  repo="$(new_repo)"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-commit base configuration"* ]]
  [[ "$output" == *"gitleaks secret scanning"* ]]
  [[ "$output" == *"Dependabot updates for pre-commit hooks"* ]]
  [[ "$output" == *"change:"* ]]
}

@test "--dry-run hides the internal ask key from the plan it prints" {
  local repo
  repo="$(new_repo)"
  printf 'default_stages: [pre-commit]\ndefault_install_hook_types: [pre-commit]\nrepos: []\n' \
    > "$repo/.pre-commit-config.yaml"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" == *"ask:"* ]]
  [[ "$output" != *"widen_hook_types"* ]]
}

@test "--help lists the pre-commit base setting" {
  run "$BIN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"pre-commit base"* ]]
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
  call precommit_base_apply "$repo"
  call gitleaks_precommit_apply "$repo"
  call dependabot_precommit_apply "$repo"
  run "$BIN" --dry-run "$repo"
  [ "$status" -eq 0 ]
  [[ "$output" != *"change:"* ]]
  [[ "$output" != *"ask:"* ]]
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
