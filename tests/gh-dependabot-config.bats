#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

GEN="$DOTFILES_ROOT/agents/skills/gh-dependabot-config/scripts/generate-dependabot-config.sh"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_DEPENDABOT_LIB_ONLY=1 source "$0"; "$@"' "$GEN" "$@"
}

# make_repo <name>: create a git repo under the test tmpdir and print its path.
# Committing matters: detection reads tracked files, so an uncommitted fixture
# would look empty.
make_repo() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  git -C "$root" init -q
  printf '%s\n' "$root"
}

commit_all() {
  git -C "$1" add -A
  git -C "$1" commit -qm fixture
}

# generate <root> [assignee]: run the script against a fixture, capturing only
# stdout so assertions read the config rather than the report.
generate() {
  run --separate-stderr bash "$GEN" --assignee "${2:-octocat}" --repo-root "$1"
}

# ─── flags & help ──────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run bash "$GEN" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: generate-dependabot-config.sh"* ]]
}

@test "an unknown flag exits non-zero" {
  run bash "$GEN" --nope
  [ "$status" -ne 0 ]
}

@test "a missing --assignee exits non-zero" {
  run bash "$GEN"
  [ "$status" -ne 0 ]
}

@test "--assignee with no value exits non-zero" {
  run bash "$GEN" --assignee
  [ "$status" -ne 0 ]
}

@test "a nonexistent --repo-root exits non-zero" {
  run bash "$GEN" --assignee octocat --repo-root "$BATS_TEST_TMPDIR/absent"
  [ "$status" -ne 0 ]
}

# ─── ecosystem_for_manifest (pure) ─────────────────────────────────────────

@test "ecosystem_for_manifest maps exact table filenames" {
  call ecosystem_for_manifest .pre-commit-config.yaml
  [ "$output" = "pre-commit" ]

  call ecosystem_for_manifest go.mod
  [ "$output" = "gomod" ]

  call ecosystem_for_manifest Cargo.toml
  [ "$output" = "cargo" ]
}

@test "ecosystem_for_manifest maps suffix families" {
  call ecosystem_for_manifest requirements-dev.txt
  [ "$output" = "pip" ]

  call ecosystem_for_manifest Api.csproj
  [ "$output" = "nuget" ]

  call ecosystem_for_manifest main.tf
  [ "$output" = "terraform" ]

  call ecosystem_for_manifest Dockerfile.prod
  [ "$output" = "docker" ]
}

@test "ecosystem_for_manifest returns nothing for an unrelated file" {
  call ecosystem_for_manifest README.md
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "ecosystem_for_manifest defers shared manifests to a resolver" {
  call ecosystem_for_manifest package.json
  [ "$output" = "@js" ]

  call ecosystem_for_manifest pyproject.toml
  [ "$output" = "@python" ]
}

# ─── resolvers (pure) ──────────────────────────────────────────────────────

@test "resolve_python_ecosystem picks uv only when uv.lock is present" {
  local d="$BATS_TEST_TMPDIR/py"
  mkdir -p "$d"
  touch "$d/pyproject.toml"

  call resolve_python_ecosystem "$d"
  [ "$output" = "pip" ]

  touch "$d/uv.lock"
  call resolve_python_ecosystem "$d"
  [ "$output" = "uv" ]
}

@test "resolve_js_ecosystem picks the ecosystem the lockfile names" {
  local d="$BATS_TEST_TMPDIR/js"
  mkdir -p "$d"
  touch "$d/package.json"

  call resolve_js_ecosystem "$d"
  [ "$output" = "npm" ]

  touch "$d/bun.lock"
  call resolve_js_ecosystem "$d"
  [ "$output" = "bun" ]
}

@test "resolve_js_ecosystem picks deno from a deno manifest" {
  local d="$BATS_TEST_TMPDIR/dn"
  mkdir -p "$d"
  touch "$d/package.json" "$d/deno.json"

  call resolve_js_ecosystem "$d"
  [ "$output" = "deno" ]
}

# ─── is_skipped_path / normalize_dir (pure) ────────────────────────────────

@test "is_skipped_path catches vendored and fixture trees" {
  call is_skipped_path node_modules/x/package.json
  [ "$status" -eq 0 ]

  call is_skipped_path vendor/dep/go.mod
  [ "$status" -eq 0 ]

  call is_skipped_path tests/fixtures/sample/package.json
  [ "$status" -eq 0 ]
}

@test "is_skipped_path leaves real source paths alone" {
  call is_skipped_path frontend/package.json
  [ "$status" -ne 0 ]

  call is_skipped_path go.mod
  [ "$status" -ne 0 ]
}

@test "is_skipped_path does not match a partial directory name" {
  call is_skipped_path buildings/package.json
  [ "$status" -ne 0 ]
}

@test "normalize_dir renders the repo root as a bare slash" {
  call normalize_dir .
  [ "$output" = "/" ]

  call normalize_dir frontend
  [ "$output" = "/frontend" ]
}

# ─── single-ecosystem repo ─────────────────────────────────────────────────

@test "a single-ecosystem repo renders exactly one entry" {
  local root
  root="$(make_repo single)"
  mkdir -p "$root/.github/workflows"
  touch "$root/.github/workflows/ci.yml"
  commit_all "$root"

  generate "$root"
  [ "$status" -eq 0 ]
  [ "$(grep -c 'package-ecosystem:' <<<"$output")" -eq 1 ]
  [[ "$output" == *"package-ecosystem: github-actions"* ]]
  [[ "$output" == *"version: 2"* ]]
}

@test "a workflow-only repo roots its entry at slash, not .github/workflows" {
  local root
  root="$(make_repo wfroot)"
  mkdir -p "$root/.github/workflows"
  touch "$root/.github/workflows/ci.yml" "$root/.github/workflows/release.yaml"
  commit_all "$root"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"directory: /"* ]]
  [[ "$output" != *".github/workflows"* ]]
  # Two workflow files still collapse to one entry.
  [ "$(grep -c 'package-ecosystem:' <<<"$output")" -eq 1 ]
}

@test "every entry carries the fixed template defaults" {
  local root
  root="$(make_repo template)"
  mkdir -p "$root/.github/workflows"
  touch "$root/.github/workflows/ci.yml" "$root/go.mod"
  commit_all "$root"

  generate "$root" hubot
  [ "$status" -eq 0 ]
  local entries
  entries="$(grep -c 'package-ecosystem:' <<<"$output")"
  [ "$entries" -eq 2 ]
  [ "$(grep -c 'interval: weekly' <<<"$output")" -eq "$entries" ]
  [ "$(grep -c 'default-days: 30' <<<"$output")" -eq "$entries" ]
  [ "$(grep -c -- '- hubot' <<<"$output")" -eq "$entries" ]
}

@test "a repo with no supported manifest exits non-zero" {
  local root
  root="$(make_repo empty)"
  touch "$root/README.md"
  commit_all "$root"

  generate "$root"
  [ "$status" -ne 0 ]
}

# ─── multi-ecosystem repo ──────────────────────────────────────────────────

# Shared fixture for the multi-ecosystem assertions: several ecosystems, one of
# them in a subdirectory, plus vendored and fixture manifests that must not
# produce entries.
make_multi_repo() {
  local root
  root="$(make_repo multi)"
  mkdir -p "$root/.github/workflows" "$root/frontend" "$root/api" "$root/infra"
  mkdir -p "$root/node_modules/evil" "$root/vendor/dep" "$root/tests/fixtures/s"
  touch "$root/.github/workflows/ci.yml"
  touch "$root/go.mod" "$root/requirements.txt"
  touch "$root/frontend/package.json"
  touch "$root/api/pyproject.toml" "$root/api/uv.lock"
  touch "$root/infra/main.tf"
  touch "$root/node_modules/evil/package.json"
  touch "$root/vendor/dep/go.mod"
  touch "$root/tests/fixtures/s/package.json"
  commit_all "$root"
  printf '%s\n' "$root"
}

@test "a multi-ecosystem repo renders an entry per detected ecosystem" {
  local root
  root="$(make_multi_repo)"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"package-ecosystem: github-actions"* ]]
  [[ "$output" == *"package-ecosystem: gomod"* ]]
  [[ "$output" == *"package-ecosystem: npm"* ]]
  [[ "$output" == *"package-ecosystem: pip"* ]]
  [[ "$output" == *"package-ecosystem: terraform"* ]]
  [[ "$output" == *"package-ecosystem: uv"* ]]
  [ "$(grep -c 'package-ecosystem:' <<<"$output")" -eq 6 ]
}

# dir_for <ecosystem> <config>: print the directory value belonging to one
# entry. A plain glob over the whole config would happily match a directory
# from a later entry, so the block is isolated first.
dir_for() {
  awk -v e="package-ecosystem: $1" '
    $0 ~ e { inblock = 1; next }
    inblock && /package-ecosystem:/ { inblock = 0 }
    inblock && /^ *directory: / { sub(/^ *directory: /, ""); print; inblock = 0 }
  ' <<<"$2"
}

@test "a multi-ecosystem repo scopes each entry to its own directory" {
  local root
  root="$(make_multi_repo)"

  generate "$root"
  [ "$status" -eq 0 ]
  [ "$(dir_for npm "$output")" = "/frontend" ]
  [ "$(dir_for uv "$output")" = "/api" ]
  [ "$(dir_for terraform "$output")" = "/infra" ]
  [ "$(dir_for gomod "$output")" = "/" ]
  [ "$(dir_for github-actions "$output")" = "/" ]
}

@test "vendored and fixture manifests produce no entries" {
  local root
  root="$(make_multi_repo)"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$output" != *"node_modules"* ]]
  [[ "$output" != *"vendor"* ]]
  [[ "$output" != *"fixtures"* ]]
  # The vendored go.mod would have added a second gomod entry.
  [ "$(grep -c 'package-ecosystem: gomod' <<<"$output")" -eq 1 ]
}

@test "the report names what was detected and what was skipped" {
  local root
  root="$(make_multi_repo)"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"Detected ecosystems:"* ]]
  [[ "$stderr" == *"uv"* ]]
  [[ "$stderr" == *"Skipped"* ]]
  [[ "$stderr" == *"node_modules/evil/package.json"* ]]
  [[ "$stderr" == *"vendor/dep/go.mod"* ]]
}

@test "the report surfaces the terraform/opentofu ambiguity" {
  local root
  root="$(make_multi_repo)"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$stderr" == *"opentofu"* ]]
}

@test "an ecosystem spanning several directories uses the directories key" {
  local root
  root="$(make_repo mono)"
  mkdir -p "$root/packages/a" "$root/packages/b"
  touch "$root/packages/a/package.json" "$root/packages/b/package.json"
  commit_all "$root"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"directories:"* ]]
  [[ "$output" == *"- /packages/a"* ]]
  [[ "$output" == *"- /packages/b"* ]]
  [ "$(grep -c 'package-ecosystem:' <<<"$output")" -eq 1 ]
}

@test "untracked manifests are ignored in a git repo" {
  local root
  root="$(make_repo untracked)"
  mkdir -p "$root/.github/workflows"
  touch "$root/.github/workflows/ci.yml"
  commit_all "$root"
  # Written but never committed: Dependabot reads the pushed tree.
  touch "$root/go.mod"

  generate "$root"
  [ "$status" -eq 0 ]
  [[ "$output" != *"gomod"* ]]
}

# ─── self-healing hook ─────────────────────────────────────────────────────

@test "--list-ecosystems prints a sorted, deduplicated list" {
  run bash "$GEN" --list-ecosystems
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf '%s\n' "$output" | sort -u)" ]
}

@test "--list-ecosystems covers the ecosystems the table can emit" {
  run bash "$GEN" --list-ecosystems
  [ "$status" -eq 0 ]
  # The resolver-only and suffix-family values never appear literally in
  # MANIFEST_TABLE, so a naive listing would miss them.
  for eco in npm bun deno pip uv nuget docker terraform opentofu github-actions; do
    [[ "$output" == *"$eco"* ]] || {
      echo "missing $eco from --list-ecosystems" >&2
      return 1
    }
  done
}
