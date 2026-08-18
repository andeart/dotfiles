#!/usr/bin/env bash
#
# Render a .github/dependabot.yml for a repository, with one updates: entry per
# package ecosystem that actually has a matching manifest checked in.
#
# The config body is written to stdout; the detection report (what was found,
# what was skipped, what needs a human decision) goes to stderr, so the two can
# be redirected apart.
#
# Usage: generate-dependabot-config.sh --assignee LOGIN [--repo-root DIR]
#
# Detection is a static filename-to-ecosystem table (see MANIFEST_TABLE below)
# rather than anything re-derived per run, so the same tree always renders the
# same file. Declaring an ecosystem with no matching manifest fails the update
# job with dependency_file_not_found, which is why nothing here is boilerplated.

set -euo pipefail

# ---------------------------------------------------------------------------
# Detection table
# ---------------------------------------------------------------------------
#
# "<glob>|<ecosystem>", matched against the basename of every tracked file.
# Ecosystems whose manifest is shared with another ecosystem (package.json,
# pyproject.toml) resolve to a placeholder that resolve_* narrows by lockfile.
#
# Every value on the right is a literal package-ecosystem value; there is no
# wildcard ecosystem, so an entry only ever appears here alongside the file
# that proves it applies.

MANIFEST_TABLE='
.pre-commit-config.yaml|pre-commit
action.yml|github-actions
action.yaml|github-actions
package.json|@js
deno.json|deno
deno.jsonc|deno
Gemfile|bundler
Cargo.toml|cargo
composer.json|composer
Dockerfile|docker
docker-compose.yml|docker-compose
docker-compose.yaml|docker-compose
compose.yml|docker-compose
compose.yaml|docker-compose
go.mod|gomod
pom.xml|maven
build.gradle|gradle
build.gradle.kts|gradle
packages.config|nuget
global.json|dotnet-sdk
requirements.txt|pip
setup.py|pip
Pipfile|pip
pyproject.toml|@python
mix.exs|hex
pubspec.yaml|pub
Package.swift|swift
build.sbt|sbt
elm.json|elm
Project.toml|julia
Chart.yaml|helm
flake.nix|nix
.gitmodules|gitsubmodule
vcpkg.json|vcpkg
environment.yml|conda
devcontainer.json|devcontainers
MODULE.bazel|bazel
WORKSPACE|bazel
WORKSPACE.bazel|bazel
rust-toolchain.toml|rust-toolchain
rust-toolchain|rust-toolchain
'

# Directories never worth an entry: their manifests belong to vendored or
# fixture trees, so an entry pointed at one raises PRs against code the repo
# does not own.
SKIP_DIRS='
.git
node_modules
vendor
third_party
.venv
venv
testdata
fixtures
__fixtures__
.terraform
dist
build
target
'

# ---------------------------------------------------------------------------
# Pure helpers
# ---------------------------------------------------------------------------

# ecosystem_for_manifest <basename>: print the ecosystem for a manifest
# filename, or nothing when the name is not a manifest. Patterns that cannot be
# expressed as a literal filename (suffix families) are handled after the table.
ecosystem_for_manifest() {
  local name="$1" line pattern eco

  while IFS= read -r line; do
    [ -n "$line" ] || continue
    pattern="${line%%|*}"
    eco="${line#*|}"
    if [ "$name" = "$pattern" ]; then
      printf '%s\n' "$eco"
      return 0
    fi
  done <<EOF
$MANIFEST_TABLE
EOF

  # Suffix and prefix families. requirements-dev.txt and friends are as much a
  # pip manifest as requirements.txt is.
  case "$name" in
    requirements*.txt)          printf 'pip\n' ;;
    *.csproj|*.vbproj|*.fsproj) printf 'nuget\n' ;;
    Dockerfile.*|*.Dockerfile)  printf 'docker\n' ;;
    *.tf)                       printf 'terraform\n' ;;
  esac
}

# is_skipped_path <relative path>: succeed when any path component is a
# directory this never descends into.
is_skipped_path() {
  local path="$1" dir

  while IFS= read -r dir; do
    [ -n "$dir" ] || continue
    case "/$path/" in
      */"$dir"/*) return 0 ;;
    esac
  done <<EOF
$SKIP_DIRS
EOF

  return 1
}

# resolve_js_ecosystem <dir>: package.json is the manifest for three ecosystems.
# The lockfile decides; npm is the fallback because it also covers yarn and pnpm.
resolve_js_ecosystem() {
  local dir="$1"

  if [ -f "$dir/bun.lock" ] || [ -f "$dir/bun.lockb" ]; then
    printf 'bun\n'
  elif [ -f "$dir/deno.json" ] || [ -f "$dir/deno.jsonc" ] || [ -f "$dir/deno.lock" ]; then
    printf 'deno\n'
  else
    printf 'npm\n'
  fi
}

# resolve_python_ecosystem <dir>: pyproject.toml alone is a pip manifest; with a
# uv lockfile beside it the project is uv's.
resolve_python_ecosystem() {
  local dir="$1"

  if [ -f "$dir/uv.lock" ]; then
    printf 'uv\n'
  else
    printf 'pip\n'
  fi
}

# normalize_dir <relative dir>: turn a dirname into a Dependabot directory
# value. "." is the repo root, which Dependabot spells "/".
normalize_dir() {
  local dir="$1"

  if [ "$dir" = "." ] || [ -z "$dir" ]; then
    printf '/\n'
  else
    printf '/%s\n' "${dir#./}"
  fi
}

# ---------------------------------------------------------------------------
# Detection
# ---------------------------------------------------------------------------

# list_candidate_files <root>: print every path Dependabot could see, relative
# to the root. Tracked files only in a git repo - Dependabot reads the pushed
# tree, so an untracked manifest would render an entry it cannot resolve.
list_candidate_files() {
  local root="$1"

  if [ -d "$root/.git" ] && command -v git >/dev/null 2>&1; then
    (cd "$root" && git ls-files)
  else
    (cd "$root" && find . -type f | sed 's|^\./||')
  fi
}

# detect_ecosystems <root>: print "<ecosystem>\t<directory>" for every entry the
# tree supports, deduplicated and sorted. Paths under a skipped directory are
# reported on the SKIPPED_FILE side channel instead.
detect_ecosystems() {
  local root="$1" rel base dir eco

  while IFS= read -r rel; do
    [ -n "$rel" ] || continue
    base="${rel##*/}"
    dir="${rel%/*}"
    [ "$dir" = "$rel" ] && dir="."

    # Workflow files carry arbitrary names, so they are matched on location
    # rather than through the basename table. The entry is always rooted at "/":
    # Dependabot looks for .github/workflows itself and an entry pointed at that
    # directory finds nothing.
    case "$rel" in
      .github/workflows/*.yml|.github/workflows/*.yaml)
        printf 'github-actions\t/\n'
        continue
        ;;
    esac

    eco="$(ecosystem_for_manifest "$base")"
    [ -n "$eco" ] || continue

    if is_skipped_path "$rel"; then
      [ -n "${SKIPPED_FILE:-}" ] && printf '%s\n' "$rel" >> "$SKIPPED_FILE"
      continue
    fi

    case "$eco" in
      @js)     eco="$(resolve_js_ecosystem "$root/$dir")" ;;
      @python) eco="$(resolve_python_ecosystem "$root/$dir")" ;;
    esac

    printf '%s\t%s\n' "$eco" "$(normalize_dir "$dir")"
  done < <(list_candidate_files "$root") | sort -u
}

# ---------------------------------------------------------------------------
# Rendering
# ---------------------------------------------------------------------------

# render_entry <ecosystem> <assignee> <dir>...: print one updates: entry.
# A single directory uses the "directory" key; several use "directories", which
# is the only one of the two that accepts globs.
render_entry() {
  local eco="$1" assignee="$2"
  shift 2

  printf '  - package-ecosystem: %s\n' "$eco"
  if [ "$#" -eq 1 ]; then
    printf '    directory: %s\n' "$1"
  else
    printf '    directories:\n'
    local d
    for d in "$@"; do
      printf '      - %s\n' "$d"
    done
  fi
  printf '    schedule:\n'
  printf '      interval: weekly\n'
  printf '    cooldown:\n'
  printf '      default-days: 30\n'
  printf '    assignees:\n'
  printf '      - %s\n' "$assignee"
}

# render_config <assignee>: read "<ecosystem>\t<directory>" pairs on stdin and
# print the whole config. Entries are grouped so an ecosystem spanning several
# directories renders once with a directories: list rather than once per path.
render_config() {
  local assignee="$1" pairs eco dirs first=1

  pairs="$(cat)"

  cat <<'EOF'
version: 2
# Let a release sit in public for a month before taking it. Security updates
# ignore cooldown, so a CVE fix still lands right away.
updates:
EOF

  while IFS= read -r eco; do
    [ -n "$eco" ] || continue
    [ "$first" -eq 1 ] || printf '\n'
    first=0
    # shellcheck disable=SC2046  # word splitting is the grouping here
    dirs=$(printf '%s\n' "$pairs" | awk -F'\t' -v e="$eco" '$1 == e { print $2 }' | sort -u)
    render_entry "$eco" "$assignee" $dirs
  done < <(printf '%s\n' "$pairs" | cut -f1 | sort -u)
}

# ---------------------------------------------------------------------------
# Reporting
# ---------------------------------------------------------------------------

# report_detection <pairs>: describe the outcome on stderr. The ambiguity note
# is the one case the table cannot settle on its own - .tf files are valid for
# both terraform and opentofu, and only the repo's own toolchain says which.
report_detection() {
  local pairs="$1" eco dirs skipped

  echo "Detected ecosystems:" >&2
  if [ -z "$pairs" ]; then
    echo "  (none - no supported manifest is checked in)" >&2
  else
    while IFS= read -r eco; do
      [ -n "$eco" ] || continue
      dirs="$(printf '%s\n' "$pairs" | awk -F'\t' -v e="$eco" '$1 == e { print $2 }' \
        | sort -u | tr '\n' ' ')"
      printf '  %-16s %s\n' "$eco" "${dirs% }" >&2
    done < <(printf '%s\n' "$pairs" | cut -f1 | sort -u)
  fi

  if [ -n "${SKIPPED_FILE:-}" ] && [ -s "$SKIPPED_FILE" ]; then
    echo >&2
    echo "Skipped (vendored or fixture path):" >&2
    sort -u "$SKIPPED_FILE" | sed 's/^/  /' >&2
  fi

  if printf '%s\n' "$pairs" | cut -f1 | grep -qx terraform; then
    echo >&2
    echo "Needs a decision: .tf files match both terraform and opentofu." >&2
    echo "  Rendered as terraform. Switch it if this repo runs OpenTofu." >&2
  fi
}

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

usage() {
  cat <<'EOF'
Usage: generate-dependabot-config.sh --assignee LOGIN [--repo-root DIR]

Prints a .github/dependabot.yml to stdout and a detection report to stderr.

  --assignee LOGIN   GitHub login to assign update PRs to (required)
  --repo-root DIR    Repository to inspect (default: current directory)
  -h, --help         Print this message
EOF
}

die() {
  echo "generate-dependabot-config.sh: $*" >&2
  exit 1
}

main() {
  local assignee="" repo_root="."

  while [ "$#" -gt 0 ]; do
    case "$1" in
      --assignee)  [ "$#" -ge 2 ] || die "--assignee needs a value"; assignee="$2"; shift 2 ;;
      --repo-root) [ "$#" -ge 2 ] || die "--repo-root needs a value"; repo_root="$2"; shift 2 ;;
      -h|--help)   usage; exit 0 ;;
      *)           usage >&2; die "unknown argument '$1'" ;;
    esac
  done

  [ -n "$assignee" ] || { usage >&2; die "--assignee is required"; }
  [ -d "$repo_root" ] || die "no such directory: $repo_root"

  SKIPPED_FILE="$(mktemp)"
  trap 'rm -f "$SKIPPED_FILE"' EXIT

  local pairs
  pairs="$(detect_ecosystems "$repo_root")"

  [ -n "$pairs" ] || die "no supported manifest found under $repo_root; nothing to write."

  report_detection "$pairs"
  printf '%s\n' "$pairs" | render_config "$assignee"
}

# Sourced with _DEPENDABOT_LIB_ONLY=1 (by tests): define functions and stop
# before parsing args or walking a tree.
if [ -n "${_DEPENDABOT_LIB_ONLY:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
