#!/usr/bin/env bash
#
# Resolve the wf-* skill family's settings for a repository.
#
# Every setting goes to stdout as one `key=value` line, defaults filled in, in a
# fixed order, with list members carrying a 1-based index. Reasons go to stderr.
#
# Usage: resolve-wf-config.sh [--repo-root DIR]
#
# Exit codes:
#   0   resolved; stdout holds every setting.
#   2   usage error.
#   3   a .wf.yml is present but wrong; stderr names the offending key.
#
# Reads .wf.yml and nothing else: no writes, no network, and one yq fork per
# run. tests/resolve-wf-config.bats pins that.

set -euo pipefail

# Distinct from 2 so a caller can tell a broken config apart from a broken
# invocation. There is no analogue of resolve-tracker.sh's exit 10 here: every
# question this script answers has a default, so it never has to ask.
EXIT_INVALID=3

# Every key the family understands, in the order the dump prints them. A `.N`
# suffix marks a list, whose members the file may set to any length.
KNOWN_SHAPES=(
  states.shaping
  states.implementing
  states.in-review
  workspace.impl
  review.reviewers.N
  review.focus.N
  ship.draft-by-default
  verify.commands.N
  wrap.watch-post-merge-ci
)

# Defaults as newline-delimited `key=value`, not a map: bash 3.2 ships on macOS
# and has no associative arrays. verify.commands is absent on purpose - see
# the test that pins it.
#
# Kept as a bare here-doc, not wrapped in $( ): bash 3.2's parser mishandles an
# apostrophe inside a quoted here-doc once it sits inside command substitution.
# Do not "tidy" this back into DEFAULTS=$(cat <<'EOF' ...).
IFS= read -r -d '' DEFAULTS <<'EOF' || true
states.shaping=Shaping
states.implementing=Implementing
states.in-review=In Review
workspace.impl=base
review.reviewers.1=Alia
review.reviewers.2=Bheem
review.reviewers.3=Cristo
review.reviewers.4=Darius
review.focus.1=Security hardening
review.focus.2=Performance
review.focus.3=Cleanliness and maintainability of code
review.focus.4=Succinct documentation that's not unnecessarily elaborate
ship.draft-by-default=true
wrap.watch-post-merge-ci=false
EOF

die() {
  echo "resolve-wf-config: $*" >&2
  exit 2
}

# invalid <message>: a config that is present but cannot be honoured. Separate
# from die() - see EXIT_INVALID above.
invalid() {
  echo "resolve-wf-config: $*" >&2
  exit "$EXIT_INVALID"
}

usage() {
  echo "Usage: resolve-wf-config.sh [--repo-root DIR]"
}

# config_path <root>: print the config path, or nothing. Root only - there is no
# tmp/ fallback, unlike the tracker config.
config_path() {
  if [ -f "$1/.wf.yml" ]; then
    printf '%s\n' "$1/.wf.yml"
  fi
}

# read_props <file>: the single yq fork. Emits `key=value`, normalising yq's
# " = " separator and its 0-based list indices.
read_props() {
  local file="$1" out
  command -v yq >/dev/null 2>&1 || die "yq is required to read .wf.yml"
  out="$(yq -o=props -- "$file")" || invalid "could not parse $file as YAML"
  printf '%s\n' "$out" | awk '
    {
      # yq -o=props emits YAML comments verbatim as their own lines. Skip them
      # before the split, or a comment containing " = " (a documented example,
      # say) is parsed as a key and rejected as unknown.
      if ($0 ~ /^[[:space:]]*#/) next
      # Split on the FIRST " = " only: a value can contain one, and splitting
      # on each would truncate it at the flag assignment.
      i = index($0, " = ")
      if (i == 0) next
      key = substr($0, 1, i - 1)
      val = substr($0, i + 3)
      # yq indexes lists from 0; the dump reads better from 1, and every
      # consumer counts reviewers rather than offsets.
      if (match(key, /\.[0-9]+$/)) {
        key = substr(key, 1, RSTART - 1) "." (substr(key, RSTART + 1) + 1)
      }
      print key "=" val
    }
  '
}

# shape_of <key>: the key with a trailing list index replaced by N.
shape_of() {
  printf '%s\n' "$1" | sed 's/\.[0-9][0-9]*$/.N/'
}

# is_known_shape <shape>: exact match, one entry at a time. Testing against the
# joined list would match any adjacent run of it.
is_known_shape() {
  local s
  for s in "${KNOWN_SHAPES[@]}"; do
    if [ "$1" = "$s" ]; then
      return 0
    fi
  done
  return 1
}

# validate <kv>: reject anything the family does not understand, naming the key.
validate() {
  local line key val shape
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    val="${line#*=}"
    shape="$(shape_of "$key")"

    if ! is_known_shape "$shape"; then
      # A list written as a scalar, or the reverse, reaches here too. Both are
      # real mistakes with a clearer name than "unknown key".
      if is_known_shape "$key.N"; then
        invalid "$key must be a list"
      fi
      if is_known_shape "${key%.*}"; then
        invalid "${key%.*} must be a single value, not a list"
      fi
      # Permanent, not a shim to pull out once the rename has propagated: a
      # stale branch, an old override, or a forgotten local copy of .wf.yml
      # can carry the retired key indefinitely, and this costs one string
      # comparison in a function whose whole job is already a lookup.
      if [ "$shape" = "ship.test-commands.N" ] || [ "$key" = "ship.test-commands" ]; then
        invalid "ship.test-commands was renamed to verify.commands"
      fi
      invalid "unknown key: $key"
    fi

    case "$val" in
      ""|"null"|"~") invalid "$key is empty; remove the key to take its default" ;;
    esac

    case "$key" in
      workspace.impl)
        case "$val" in
          base|worktree) ;;
          *) invalid "workspace.impl must be base or worktree, not '$val'" ;;
        esac ;;
      ship.draft-by-default|wrap.watch-post-merge-ci)
        case "$val" in
          true|false) ;;
          *) invalid "$key must be true or false, not '$val'" ;;
        esac ;;
    esac
  done <<EOF
$1
EOF
}

# lines_under <kv> <prefix>: every `prefix.<n>=` line, in the order given.
lines_under() {
  printf '%s\n' "$1" | awk -v p="$2." 'index($0, p) == 1'
}

# line_for <kv> <key>: the single `key=` line, or nothing.
line_for() {
  printf '%s\n' "$1" | awk -v k="$2=" 'index($0, k) == 1'
}

# emit <kv>: print every setting in KNOWN_SHAPES order, file values winning over
# defaults. A list set in the file replaces its default outright rather than
# appending, so a two-name roster means two cycles and not six.
emit() {
  local kv="$1" shape prefix found
  for shape in "${KNOWN_SHAPES[@]}"; do
    case "$shape" in
      *.N)
        prefix="${shape%.N}"
        found="$(lines_under "$kv" "$prefix")"
        if [ -z "$found" ]; then
          found="$(lines_under "$DEFAULTS" "$prefix")"
        fi
        ;;
      *)
        found="$(line_for "$kv" "$shape")"
        if [ -z "$found" ]; then
          found="$(line_for "$DEFAULTS" "$shape")"
        fi
        ;;
    esac
    if [ -n "$found" ]; then
      printf '%s\n' "$found"
    fi
  done
}

# resolve <root>: the whole decision. See the exit codes above.
resolve() {
  local root="$1" file kv
  [ -d "$root" ] || die "no such directory: $root"
  file="$(config_path "$root")"
  if [ -z "$file" ]; then
    emit ""
    return 0
  fi
  kv="$(read_props "$file")"
  validate "$kv"
  emit "$kv"
}

main() {
  local repo_root="."
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo-root)
        # Emptiness matters as much as arity: an empty value would resolve the
        # working directory, which is not what an explicit flag asked for.
        { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--repo-root needs a value"
        repo_root="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage >&2; die "unknown argument: $1" ;;
    esac
  done

  resolve "$repo_root"
}

# Sourced with _WF_LIB_ONLY=1 (by tests): define functions and stop before
# parsing args or reading a tree.
if [ -n "${_WF_LIB_ONLY:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
