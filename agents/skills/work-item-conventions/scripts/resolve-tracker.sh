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
# Stats and reads .workitems.<tracker>.yml, plus - only when the root carries
# none - the worktree's .git pointer and the back-reference git writes beside
# the registration it names. No writes, no network, no subprocess it did not
# spawn itself. tests/resolve-tracker.bats pins that, and RESOLUTION.md says
# why it matters.

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

# base_clone and POINTER_MAX, shared with resolve-wf-config.sh. Sourced above
# the library-mode return below, because tests/resolve-tracker.bats calls into
# this script under _WORKITEMS_LIB_ONLY=1 - moved below it, those cases invoke
# an undefined function.
#
# These eight lines are byte-identical in resolve-wf-config.sh and have to be:
# nothing can source the helper to find out where the helper is. base-clone.sh's
# header carries why the expansion rather than $(dirname ...), and why the case
# arm - one copy, since it is one decision.
case "${BASH_SOURCE[0]}" in
  */*) _helper="${BASH_SOURCE[0]%/*}" ;;
  *) _helper=. ;;
esac
_helper="$_helper/../../git-conventions/scripts/base-clone.sh"
[ -f "$_helper" ] || die "missing $_helper - run 'dotfiles push' to sync the skills"
. "$_helper"
unset _helper

# The directory this run reads configs from, and the trackers found under it.
# Top-level for the reason resolve-wf-config.sh gives for INHERITED_FROM: tests
# source this script under `set -u`, where reading an unset name exits 1 instead
# of the code the caller is testing for.
SEARCH_ROOT=""
SEARCH_CANDIDATES=""

# The path config_path_for last resolved. Together with SEARCH_CANDIDATES above
# these delete five command substitutions per sweep - four inside the loop and
# the one around it - which was the largest single cost here.
CONFIG_PATH=""

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

# has_line <lines> <value>: whether <value> is one whole line of <lines>. The
# `grep -qxF` this replaces was a fork and a pipeline to answer a question about
# four short strings. Quoted in the pattern, so a `*` in a value read out of a
# config is matched literally - which is what -F bought.
has_line() {
  case $'\n'"$1"$'\n' in
    *$'\n'"$2"$'\n'*) return 0 ;;
  esac
  return 1
}

# What unique_lines last produced. Assigns rather than prints, for the reason
# CONFIG_PATH does: read back through a command substitution this costs a
# subshell whatever happens inside it.
UNIQUE_LINES=""
LINE_COUNT=0

# unique_lines <string>: assign <string>'s distinct non-empty lines, first
# occurrence order, to UNIQUE_LINES, and how many there are to LINE_COUNT. Pure
# shell: it replaces a `sort -u | grep .` pipeline and a `grep -c .` one, three
# processes and two subshells between them, on values that are never more than
# four short lines.
#
# First-occurrence rather than sorted, which is what `sort -u` gave: the caller
# feeds this the candidates' declared defaults in candidate order, so the
# disagreement message now lists them in the order the candidates print above
# it rather than alphabetically.
#
# Peeled one line at a time rather than split on IFS: a default_tracker value
# read out of a config reaches here, and unquoted word splitting would glob a
# `*` in it against the working directory.
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
# for public repos where a root-level config would look out of place.
#
# Assigns rather than prints, and has no caller outside this file: read back
# through a command substitution one lookup costs a subshell whatever it finds,
# and a sweep calls this once per tracker. Cleared first, because a value left
# behind would report every tracker as configured.
config_path_for() {
  local root="$1" tracker="$2"
  CONFIG_PATH=""
  if [ -f "$root/.workitems.$tracker.yml" ]; then
    CONFIG_PATH="$root/.workitems.$tracker.yml"
  elif [ -f "$root/tmp/.workitems.$tracker.yml" ]; then
    CONFIG_PATH="$root/tmp/.workitems.$tracker.yml"
  fi
}

# discover_trackers <root>: assign every tracker with a config under <root> to
# SEARCH_CANDIDATES, newline-separated. Assigns for the reason config_path_for
# does, and it is the larger half: read back through $() a sweep pays one
# subshell for the loop on top of the four inside it.
discover_trackers() {
  local root="$1" t
  SEARCH_CANDIDATES=""
  for t in "${KNOWN_TRACKERS[@]}"; do
    config_path_for "$root" "$t"
    [ -n "$CONFIG_PATH" ] || continue
    SEARCH_CANDIDATES="${SEARCH_CANDIDATES}${SEARCH_CANDIDATES:+$'\n'}$t"
  done
}

# set_search_root <root>: decide once which directory this run reads. The root's
# own when it carries any config; otherwise the base clone it was cut from, when
# it is a linked worktree. One directory answers the whole run, so a worktree
# carrying its own config for one tracker never has the base clone's config for
# another mixed into its candidate set - see the design doc for what a
# per-tracker fallback does to that set, and for what a third sweep costs.
#
# The is-a-file test is a hoisted copy of base_clone's first test, so an
# ordinary clone with no config pays a stat rather than a fork. A base_clone
# that declines leaves SEARCH_ROOT as the root it was given, so every message
# below names a real directory either way.
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

# emit_answer <tracker> <with_path>: the one place an exit-0 answer is printed.
# All three return points below reach it, so a bare name and the key=value pair
# cannot drift into two spellings of one contract.
#
# The path comes from $SEARCH_ROOT and never from $root: one run reads one
# directory, and reaching for $root here is how a reimplementation ends up
# answering from two at once.
#
# Unlike the four stderr messages, this puts a caller-supplied path on stdout,
# into a line a skill reads by field - where a newline in a directory name
# forges another one. Same pattern base_clone carries for its own output, for
# the same reason. Rejected at 2 rather than printed empty: empty already means
# "no config under the search root", and the root is the caller's own argument.
#
# The message names the flag and never the value. Interpolating the path here
# would put the bytes this branch exists to reject onto stderr instead, in a
# line file-work-item/SKILL.md tells an agent to show the user verbatim - a
# newline in the root then forges the config_path= field one line up refused.
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
      # A path was asked for, so this branch has to stat after all: the check
      # and the search root the detection path runs below. Off the flag it
      # still opens nothing and still resolves where the root does not exist,
      # which is what tests/resolve-tracker.bats pins. is_known_tracker gates
      # both, so the name is validated before it is interpolated into a path.
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

  # Every message below names $root, and all of them stay correct because $root
  # is now the directory the candidates actually came from.
  set_search_root "$root"
  root="$SEARCH_ROOT"

  local candidates count
  candidates="$SEARCH_CANDIDATES"
  unique_lines "$candidates"
  count="$LINE_COUNT"

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
