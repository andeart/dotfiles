#!/usr/bin/env bash
#
# Resolve which issue tracker a repository files work items into.
#
# The resolved tracker name goes to stdout. When the run cannot narrow the
# answer to one tracker, the candidates go to stdout and the reason goes to
# stderr, so a caller can render a prompt without parsing prose.
#
# Usage: resolve-tracker.sh [--repo-root DIR] [--tracker NAME]
#
# Exit codes:
#   0   resolved; stdout holds the tracker name.
#   10  needs a human; stdout holds the candidates, one per line (possibly
#       none), stderr says why they could not be narrowed to one.
#   2   usage error.
#
# Stats and reads .workitems.<tracker>.yml and nothing else: no writes, no
# network, no subprocess it did not spawn itself. tests/resolve-tracker.bats
# pins that, and RESOLUTION.md says why it matters.

set -euo pipefail

# Every tracker with a reference file under ../references/. A name absent here
# is a typo rather than a tracker, and resolving it would send the caller
# looking for mechanics that do not exist.
KNOWN_TRACKERS=(plane github jira gitlab)

# Distinct from 1 so a caller can tell "ask the user" apart from the script
# itself failing.
EXIT_ASK=10

die() {
  echo "resolve-tracker: $*" >&2
  exit 2
}

usage() {
  echo "Usage: resolve-tracker.sh [--repo-root DIR] [--tracker NAME]"
}

# known_trackers: print every tracker this script can resolve to.
known_trackers() {
  printf '%s\n' "${KNOWN_TRACKERS[@]}"
}

# is_known_tracker <name>: exact match, one entry at a time. Testing against the
# joined list resolves any adjacent run of it - `plane github` matched, and sent
# the caller at a reference file that does not exist.
is_known_tracker() {
  local t
  for t in "${KNOWN_TRACKERS[@]}"; do
    if [ "$1" = "$t" ]; then
      return 0
    fi
  done
  return 1
}

# count_lines: number of non-empty lines on stdin. grep exits 1 for no matches
# and 2 for a real error; only the first is an answer of zero.
count_lines() {
  grep -c . || [ $? -eq 1 ]
}

# config_path_for <root> <tracker>: print the config path for one tracker, or
# nothing. The repo root wins over tmp/, which exists for public repos where a
# root-level config would look out of place.
config_path_for() {
  local root="$1" tracker="$2"
  if [ -f "$root/.workitems.$tracker.yml" ]; then
    printf '%s\n' "$root/.workitems.$tracker.yml"
  elif [ -f "$root/tmp/.workitems.$tracker.yml" ]; then
    printf '%s\n' "$root/tmp/.workitems.$tracker.yml"
  fi
}

# discover_trackers <root>: print every tracker with a config, one per line.
discover_trackers() {
  local root="$1" t
  for t in "${KNOWN_TRACKERS[@]}"; do
    if [ -n "$(config_path_for "$root" "$t")" ]; then
      printf '%s\n' "$t"
    fi
  done
}

# declared_default <config>: print the config's top-level default_tracker
# value, or nothing. Only column 0 counts, so a commented-out or nested key is
# not a declaration.
#
# The body is gh-set-default-settings' plane_config_value with the key fixed;
# that function's comment carries why nothing interior is scrubbed, and
# tests/resolve-tracker.bats pins the two together.
declared_default() {
  local file="$1"
  [ -n "$file" ] && [ -f "$file" ] || return 0
  awk '
    index($0, "default_tracker:") == 1 {
      sub(/^default_tracker[[:space:]]*:[[:space:]]*/, "")
      sub(/^#.*$/, "")
      sub(/[[:space:]]+#.*$/, "")
      sub(/[[:space:]]+$/, "")
      gsub(/^["\047]+|["\047]+$/, "")
      sub(/[[:space:]]+$/, "")
      print
      exit
    }
  ' "$file"
}

# resolve <root> [explicit]: the whole decision. See the exit codes above.
resolve() {
  local root="$1" explicit="${2:-}"

  # 1. An explicitly named tracker wins outright, and repo config is never
  #    opened. "File a Jira ticket" is an instruction, not a hint to weigh
  #    against whatever happens to be checked in.
  if [ -n "$explicit" ]; then
    if is_known_tracker "$explicit"; then
      printf '%s\n' "$explicit"
      return 0
    fi
    die "unknown tracker: $explicit (known: ${KNOWN_TRACKERS[*]})"
  fi

  # Only detection needs a tree. Naming a tracker outright answers the question
  # without opening anything, so it should not depend on where it was run.
  [ -d "$root" ] || die "no such directory: $root"

  local candidates count
  candidates="$(discover_trackers "$root")"
  count="$(printf '%s\n' "$candidates" | count_lines)"

  # 2. One config is unambiguous on its own; default_tracker is not consulted,
  #    so a repo on a single tracker never has to carry the key.
  if [ "$count" -eq 1 ]; then
    printf '%s\n' "$candidates"
    return 0
  fi

  if [ "$count" -eq 0 ]; then
    echo "no .workitems.<tracker>.yml under $root or $root/tmp" >&2
    return "$EXIT_ASK"
  fi

  # 3. More than one. Collect what the candidates declare, reading the config
  #    that wins for each tracker rather than one designated file, so the key
  #    can be set in whichever tracker's config the user happens to open.
  local declared="" t d
  for t in $candidates; do
    d="$(declared_default "$(config_path_for "$root" "$t")")"
    if [ -n "$d" ]; then
      declared="${declared}${d}"$'\n'
    fi
  done
  declared="$(printf '%s' "$declared" | sort -u | grep . || true)"

  local n_declared
  n_declared="$(printf '%s\n' "$declared" | count_lines)"

  # 4. Anything short of one agreed, resolvable default goes back to the user.
  #    Picking for them here is how a work item lands in the wrong tracker.
  if [ "$n_declared" -eq 0 ]; then
    printf '%s\n' "$candidates"
    echo "$count tracker configs under $root, and none sets default_tracker" >&2
    return "$EXIT_ASK"
  fi

  if [ "$n_declared" -gt 1 ]; then
    printf '%s\n' "$candidates"
    echo "tracker configs under $root disagree on default_tracker: $(printf '%s' "$declared" | tr '\n' ' ')" >&2
    return "$EXIT_ASK"
  fi

  # Ordered before the candidate match so a typo is reported as a typo. Both
  # checks reject an unknown name, but the candidate match can only say the
  # value has no config, which sends the user looking for a missing file rather
  # than at the misspelling in front of them.
  if ! is_known_tracker "$declared"; then
    printf '%s\n' "$candidates"
    echo "default_tracker names '$declared', which is not a tracker (known: ${KNOWN_TRACKERS[*]})" >&2
    return "$EXIT_ASK"
  fi

  # A default naming a tracker with no config is a stale edit. Honouring it
  # would file into a tracker this repo holds no settings for.
  if ! printf '%s\n' "$candidates" | grep -qxF "$declared"; then
    printf '%s\n' "$candidates"
    echo "default_tracker names '$declared', which has no config under $root" >&2
    return "$EXIT_ASK"
  fi

  printf '%s\n' "$declared"
}

main() {
  local repo_root="." explicit=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo-root)
        { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--repo-root needs a value"
        repo_root="$2"; shift 2 ;;
      --tracker)
        # Emptiness matters as much as arity here: an empty value would fall
        # through to detection, which is the one thing naming a tracker is
        # supposed to prevent.
        { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--tracker needs a value"
        explicit="$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage >&2; die "unknown argument: $1" ;;
    esac
  done

  resolve "$repo_root" "$explicit"
}

# Sourced with _WORKITEMS_LIB_ONLY=1 (by tests): define functions and stop
# before parsing args or reading a tree.
if [ -n "${_WORKITEMS_LIB_ONLY:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
