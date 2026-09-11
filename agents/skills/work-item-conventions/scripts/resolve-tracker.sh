#!/usr/bin/env bash
#
# Resolve which issue tracker a repository files work items into.
#
# The resolved tracker name goes to stdout. When the run cannot narrow the
# answer to one tracker, the candidates go to stdout and the reason goes to
# stderr, so a caller can render a prompt without parsing prose.
#
# Usage: resolve-tracker.sh [--repo-root DIR] [--tracker NAME]
#                           [--with-config-path]
#
# Exit codes:
#   0   resolved; stdout holds the tracker name, or `tracker=` and
#       `config_path=` under --with-config-path.
#   10  needs a human; stdout holds the candidates, one per line (possibly
#       none), stderr says why they could not be narrowed to one. Never
#       key=value, whatever flags were passed.
#   2   usage error; a shipped file this script needs is missing; or a root
#       --with-config-path was asked to print a path for carries a control
#       character.
#
# This script stats and reads .workitems.<tracker>.yml. When the root carries
# no config, it also reads the worktree's .git pointer, and the back-reference
# that git writes beside the registration that pointer names. It writes nothing,
# it uses no network, and it runs no subprocess that it did not start itself.
# tests/resolve-tracker.bats grades that, and RESOLUTION.md says why it
# matters.

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
  echo "Usage: resolve-tracker.sh [--repo-root DIR] [--tracker NAME] [--with-config-path]"
}

# base_clone and POINTER_MAX, shared with resolve-wf-config.sh. This source
# must stay above the library-mode return below: tests/resolve-tracker.bats
# calls into this script under _WORKITEMS_LIB_ONLY=1, and a source below that
# return leaves the function undefined.
#
# resolve-wf-config.sh holds the same eight lines, because nothing can source
# the helper to find where the helper is. The two copies are identical only
# while both callers stay two levels below agents/skills/. The hook, the third
# consumer, uses an absolute path instead. tests/resolve-wf-config.bats grades
# the two copies together. base-clone.sh's header gives the rest.
case "${BASH_SOURCE[0]}" in
  */*) _helper="${BASH_SOURCE[0]%/*}" ;;
  *) _helper=. ;;
esac
_helper="$_helper/../../git-conventions/scripts/base-clone.sh"
[ -f "$_helper" ] || die "missing $_helper - run 'dotfiles push' to sync the skills"
. "$_helper"
unset _helper

# The directory this run reads configs from, the trackers found below it, and
# how many there are. These are top-level for the reason resolve-wf-config.sh
# gives for INHERITED_FROM: the tests source this script under `set -u`, where a
# read of an unset name exits 1 instead of the code the caller tests for.
#
# discover_trackers sets the count beside the list, so the branch that counts
# candidates and the branch that emits one read the same answer. A count from a
# second pass that removes duplicates disagrees with the list as soon as
# KNOWN_TRACKERS holds a repeated entry, and --with-config-path then prints a
# `tracker=` field of two lines. tests/resolve-tracker.bats grades the list
# distinct at the source.
SEARCH_ROOT=""
SEARCH_CANDIDATES=""
SEARCH_COUNT=0

# The path config_path_for last resolved. With SEARCH_CANDIDATES above, the
# assign-only contract keeps five command substitutions out of each sweep: four
# in discover_trackers' loop, and one around that loop.
CONFIG_PATH=""

# known_trackers: print every tracker this script can resolve to.
known_trackers() {
  printf '%s\n' "${KNOWN_TRACKERS[@]}"
}

# is_known_tracker <name>: exact match, one entry at a time. A test against the
# joined list also matches an adjacent run of entries, such as `plane github`,
# which names no reference file.
is_known_tracker() {
  local t
  for t in "${KNOWN_TRACKERS[@]}"; do
    if [ "$1" = "$t" ]; then
      return 0
    fi
  done
  return 1
}

# has_line <lines> <value>: report whether <value> is one full line of <lines>.
# Pure shell, because a fork and a pipeline are too much for a question about
# four short strings. The value is quoted in the pattern, so a `*` in a value
# read from a config matches literally.
has_line() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# What unique_lines last produced. These assign, for the reason CONFIG_PATH
# does: a caller that reads a print through a command substitution pays a
# subshell on each call.
UNIQUE_LINES=""
LINE_COUNT=0

# unique_lines <string>: assign the distinct non-empty lines of <string>, in
# first-occurrence order, to UNIQUE_LINES, and how many there are to LINE_COUNT.
# Pure shell, because these values are never more than four short lines.
#
# First-occurrence order, and not sorted order: the caller gives the candidates'
# declared defaults in candidate order, so the disagreement message lists them
# in the order the candidates print above it.
#
# The loop takes one line at a time and does not split on IFS. A default_tracker
# value from a config reaches here, and an unquoted split expands a `*` in it
# against the working directory.
unique_lines() {
  local rest="$1" line
  UNIQUE_LINES=""
  LINE_COUNT=0
  while [ -n "$rest" ]; do
    line="${rest%%$'\n'*}"
    if [ "$line" = "$rest" ]; then
      rest=""
    else
      rest="${rest#*$'\n'}"
    fi
    [ -n "$line" ] || continue
    has_line "$UNIQUE_LINES" "$line" && continue
    UNIQUE_LINES="${UNIQUE_LINES}${UNIQUE_LINES:+$'\n'}$line"
    LINE_COUNT=$((LINE_COUNT + 1))
  done
}

# config_path_for <root> <tracker>: assign the config path for one tracker to
# CONFIG_PATH, or the empty string. The repo root wins over tmp/, which exists
# for public repos where a root-level config looks out of place.
#
# This function assigns, and it has no caller outside this file: a sweep calls
# it once per tracker, and a command substitution costs a subshell on each call.
# It clears CONFIG_PATH first, because a value left from the last call reports
# every tracker as configured.
config_path_for() {
  local root="$1" tracker="$2"
  CONFIG_PATH=""
  if [ -f "$root/.workitems.$tracker.yml" ]; then
    CONFIG_PATH="$root/.workitems.$tracker.yml"
  elif [ -f "$root/tmp/.workitems.$tracker.yml" ]; then
    CONFIG_PATH="$root/tmp/.workitems.$tracker.yml"
  fi
}

# discover_trackers <root>: assign each tracker with a config below <root> to
# SEARCH_CANDIDATES, one per line, and how many there are to SEARCH_COUNT. It
# assigns for the reason config_path_for does, and it saves the larger half:
# through $() a sweep pays one subshell for the loop, and four more inside
# it.
discover_trackers() {
  local root="$1" t
  SEARCH_CANDIDATES=""
  SEARCH_COUNT=0
  for t in "${KNOWN_TRACKERS[@]}"; do
    config_path_for "$root" "$t"
    [ -n "$CONFIG_PATH" ] || continue
    SEARCH_CANDIDATES="${SEARCH_CANDIDATES}${SEARCH_CANDIDATES:+$'\n'}$t"
    SEARCH_COUNT=$((SEARCH_COUNT + 1))
  done
}

# set_search_root <root>: decide once which directory this run reads. It reads
# the root itself when the root carries any config. If not, and the root is a
# linked worktree, it reads the base clone that worktree was cut from.
#
# One directory answers the whole run. So a worktree that carries its own config
# for one tracker never mixes the base clone's config for another tracker into
# its candidate set. A per-tracker fallback reports both, and sends a repo that
# resolves cleanly to an exit-10 ask. The case named "a worktree's own config
# wins outright" in tests/resolve-tracker.bats grades that.
#
# The is-a-file test is a copy of base_clone's first test, so a root with no
# config pays a stat and not a fork. That is every run in a repo with no tracker
# config, and not a rare branch. Keep it the same test on the same path: it is
# behaviour-identical by construction, so no case here fails if base_clone's
# first line moves.
#
# A base_clone that declines leaves SEARCH_ROOT as the given root, so each
# message below names a real directory.
set_search_root() {
  local base
  SEARCH_ROOT="$1"
  discover_trackers "$1"
  [ -z "$SEARCH_CANDIDATES" ] || return 0
  [ -f "$1/.git" ] || return 0
  base="$(base_clone "$1")"
  [ -n "$base" ] || return 0
  SEARCH_ROOT="$base"
  discover_trackers "$base"
}

# declared_default <config>: print the config's top-level default_tracker
# value, or print nothing. Only column 0 counts, so a key that is commented out
# or nested is not a declaration.
#
# The body is plane_config_value from gh-set-default-settings with the key
# fixed. That function's comment says why it cleans nothing inside the value,
# and tests/resolve-tracker.bats grades the two together.
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

# emit_answer <tracker> <with_path>: the one place that prints an exit-0 answer.
# All three return points below use it, so the bare name and the key=value pair
# stay one contract in one spelling.
#
# The path comes from $SEARCH_ROOT and never from $root. One run reads one
# directory, and a read of $root here answers from two directories at once.
#
# The four stderr messages carry prose. This line carries a caller-supplied path
# on stdout, in a field a skill reads by name, where a newline in a directory
# name makes a second field. base_clone uses the same pattern on its own output,
# for the same reason. A path with a control character exits 2 and prints
# nothing, and the message names the flag and not the value.
# tests/resolve-tracker.bats grades both halves and says why each one is this
# way round.
emit_answer() {
  local tracker="$1" with_path="$2"
  if [ "$with_path" != yes ]; then
    printf '%s\n' "$tracker"
    return 0
  fi
  config_path_for "$SEARCH_ROOT" "$tracker"
  case "$CONFIG_PATH" in
    *[[:cntrl:]]*) die "--repo-root resolves to a path carrying a control character" ;;
  esac
  printf 'tracker=%s\nconfig_path=%s\n' "$tracker" "$CONFIG_PATH"
}

# resolve <root> [explicit] [with_path]: the whole decision. See the exit codes
# above.
resolve() {
  local root="$1" explicit="${2:-}" with_path="${3:-}"

  # 1. An explicitly named tracker wins outright, and repo config is never
  #    opened. "File a Jira ticket" is an instruction, not a hint to weigh
  #    against whatever happens to be checked in.
  if [ -n "$explicit" ]; then
    if is_known_tracker "$explicit"; then
      # A request for a path makes this branch stat after all: the root test
      # and the search root that the detection path below uses. Without the
      # flag, this branch opens nothing and resolves even where the root does
      # not exist, which tests/resolve-tracker.bats grades. is_known_tracker
      # gates both, so the name is valid before it goes into a path.
      if [ "$with_path" = yes ]; then
        [ -d "$root" ] || die "no such directory: $root"
        set_search_root "$root"
      fi
      emit_answer "$explicit" "$with_path"
      return 0
    fi
    die "unknown tracker: $explicit (known: ${KNOWN_TRACKERS[*]})"
  fi

  # Only detection needs a tree. Naming a tracker outright answers the question
  # without opening anything, so it should not depend on where it was run.
  [ -d "$root" ] || die "no such directory: $root"

  # $root becomes the directory the candidates came from, so each message below
  # names that directory.
  set_search_root "$root"
  root="$SEARCH_ROOT"

  local candidates count
  candidates="$SEARCH_CANDIDATES"
  count="$SEARCH_COUNT"

  # 2. One config is unambiguous on its own; default_tracker is not consulted,
  #    so a repo on a single tracker never has to carry the key.
  if [ "$count" -eq 1 ]; then
    emit_answer "$candidates" "$with_path"
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
    config_path_for "$root" "$t"
    d="$(declared_default "$CONFIG_PATH")"
    if [ -n "$d" ]; then
      declared="${declared}${d}"$'\n'
    fi
  done
  unique_lines "$declared"
  declared="$UNIQUE_LINES"

  local n_declared="$LINE_COUNT"

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
  if ! has_line "$candidates" "$declared"; then
    printf '%s\n' "$candidates"
    echo "default_tracker names '$declared', which has no config under $root" >&2
    return "$EXIT_ASK"
  fi

  emit_answer "$declared" "$with_path"
}

main() {
  local repo_root="." explicit="" with_path=""
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
      --with-config-path)
        with_path=yes; shift ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage >&2; die "unknown argument: $1" ;;
    esac
  done

  resolve "$repo_root" "$explicit" "$with_path"
}

# Sourced with _WORKITEMS_LIB_ONLY=1 (by tests): define functions and stop
# before parsing args or reading a tree.
if [ -n "${_WORKITEMS_LIB_ONLY:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
