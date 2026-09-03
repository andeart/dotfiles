#!/usr/bin/env bash
#
# Resolve the wf-* skill family's settings for a repository.
#
# Every key the family understands emits at least one line, in a fixed order:
# `key=value` for a value the file set, `key.1=`/`key.2=` for a list it set,
# `key=<none>` for a list it emptied, and `key=<unset>` for a key it did not
# declare. Reasons go to stderr.
#
# Usage: resolve-wf-config.sh [--repo-root DIR] [--require KEY[,KEY...]]
#
# Exit codes:
#   0   resolved; stdout holds every setting.
#   2   usage error.
#   3   a .wf.yml is present but wrong; stderr names the offending key.
#   4   a --require key the file never declared; stderr carries the halt message.
#
# Reads .wf.yml and nothing else: no writes, no network, and one yq fork per
# run, bounded by YQ_TIMEOUT below. tests/resolve-wf-config.bats pins that.

set -euo pipefail

# Distinct from 2 so a caller can tell a broken config apart from a broken
# invocation. An unset key is neither: the file is incomplete rather than
# malformed, so it resolves at 0 with `<unset>` and each consumer decides.
EXIT_INVALID=3

# Opt-in, and only reachable through --require. A caller that names no key never
# sees it, which is what lets /wf-wrap read a key without gaining a way to fail
# after its cleanup has already run.
EXIT_UNSET=4

# Every key the family understands, in the order the dump prints them. A `.N`
# suffix marks a list, whose members the file may set to any length. The values
# a repo starts from live in wf.yml.template beside this script; nothing here
# falls back.
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

# halt <message>: a --require key the file never declared. Unprefixed, unlike
# die() and invalid(): a skill prints this line to the user verbatim, and the
# script's own name in front of it would read as a crash rather than an answer.
halt() {
  echo "$*" >&2
  exit "$EXIT_UNSET"
}

usage() {
  echo "Usage: resolve-wf-config.sh [--repo-root DIR] [--require KEY[,KEY...]]"
}

# config_path <root>: print the config path, or nothing. Root only - there is no
# tmp/ fallback, unlike the tracker config.
config_path() {
  if [ -f "$1/.wf.yml" ]; then
    printf '%s\n' "$1/.wf.yml"
  fi
}

# Wall clock the one yq fork gets. Nested YAML aliases expand multiplicatively,
# so a .wf.yml under 300 bytes can hold yq past any deadline at full CPU, which
# no cap on size or depth reaches. /wf-config is what makes the bound necessary
# rather than merely tidy: every other caller also runs that repo's
# verify.commands verbatim, so for them a hang is the least of what an untrusted
# file already does, while /wf-config runs no command and a hang is the whole of
# it. AGENTS.md also requires a SKILL.md block to fit inside the Bash tool's
# timeout, and six of them fork this script.
YQ_TIMEOUT="${WF_YQ_TIMEOUT:-10}"
case "$YQ_TIMEOUT" in
  ''|*[!0-9]*) die "WF_YQ_TIMEOUT must be a whole number of seconds" ;;
esac

# 128 + SIGTERM: what the watchdog's kill leaves as the fork's status.
YQ_TIMEOUT_RC=143

# read_props <file>: the single yq fork. Emits `key=value`, normalising yq's
# " = " separator and its 0-based list indices.
#
# The expression rewrites every empty sequence to a one-member sentinel first.
# yq -o=props drops an empty sequence entirely, so `reviewers: []` would emit no
# lines and be indistinguishable from an absent key. Traversing the whole
# document rather than the known keys also gives `bogus: []` and a scalar
# written as `[]` a line to be rejected on. It does not reach an empty map:
# `{}` is still dropped, so a list mistyped as a map reports <unset>.
read_props() {
  local file="$1" out rc=0
  command -v yq >/dev/null 2>&1 || die "yq is required to read .wf.yml"
  # The fork runs on a leash held by a sleeping subshell. No temp file: the
  # watchdog's own output goes to /dev/null so it cannot hold the command
  # substitution open, and a temp-file capture would need the `rm` this repo's
  # deletion hook blocks. `wait ... || rc=$?` rather than `; rc=$?` because
  # `set -e` is in force inside the subshell too.
  out="$(
    yq -o=props '(.. | select(tag == "!!seq" and length == 0)) |= ["<none>"]' -- "$file" &
    parser=$!
    { sleep "$YQ_TIMEOUT"; kill -TERM "$parser" 2>/dev/null; } >/dev/null 2>&1 &
    watchdog=$!
    rc=0
    wait "$parser" || rc=$?
    kill "$watchdog" 2>/dev/null || :
    exit "$rc"
  )" || rc=$?
  if [ "$rc" -eq "$YQ_TIMEOUT_RC" ]; then
    invalid "gave up parsing $file after ${YQ_TIMEOUT}s; a YAML alias chain can expand without bound"
  fi
  [ "$rc" -eq 0 ] || invalid "could not parse $file as YAML"
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
# Stays separate from read_props's awk: emit walks KNOWN_SHAPES, so an unknown
# key never survives it, and merging the two would retire the unknown-key
# rejection along with it.
validate() {
  local line key val shape base seen="|" none_prefix=""
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    key="${line%%=*}"
    val="${line#*=}"
    # A trailing list index becomes N so a member matches its list's shape.
    # Test the last segment rather than globbing digits, which would cap the
    # index length this accepts.
    case "${key##*.}" in
      ''|*[!0-9]*) shape="$key" ;;
      *) shape="${key%.*}.N" ;;
    esac

    if ! is_known_shape "$shape"; then
      # A root-level sequence indexes straight to a bare number, so reporting it
      # as an unknown key would name a `0` the file never spelled and send the
      # reader looking for it.
      case "$key" in
        ''|*[!0-9]*) ;;
        *) invalid "the document's root is a list; .wf.yml must be a mapping of keys" ;;
      esac
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
      # Every trailing index walked off, not just one. A nested sequence
      # indexes twice (`review.reviewers.0.1`), and dropping a single index
      # would expose yq's raw 0-based inner index - a position the file never
      # spelled, and the opposite of the 1-based dump every other line promises.
      base="$key"
      while :; do
        case "$base" in
          *.*) ;;
          *) break ;;
        esac
        case "${base##*.}" in
          ''|*[!0-9]*) break ;;
          *) base="${base%.*}" ;;
        esac
      done
      if [ "$base" != "$key" ] && is_known_shape "$base.N"; then
        invalid "$base must be a list of single values, not a nested list"
      fi
      # The sentinel rewrite hands an unknown `bogus: []` the key `bogus.1`, an
      # index the file never had. Key on the walked-down name rather than on the
      # sentinel, so `bogus: [Ana]` - the same mistake - reports the same name.
      case "$shape" in
        *.N) invalid "unknown key: $base" ;;
      esac
      invalid "unknown key: $key"
    fi

    # yq collapses duplicate keys inside one document, so only a multi-document
    # file reaches here - flattened by -o=props into two lines for one key,
    # which would put a second `key=` line in front of every skill-side check.
    # `|`-delimited because bash 3.2 has no associative arrays; only known keys
    # reach it, and none of them contains a `|`.
    case "$seen" in
      *"|$key|"*) invalid "$key is set more than once" ;;
    esac
    seen="$seen$key|"

    # Set by the <none> arm below when a list's first member is the marker.
    # props keeps document order, so a further member under the same prefix
    # arrives after it.
    if [ -n "$none_prefix" ]; then
      case "$key" in
        "$none_prefix".*) invalid "$none_prefix lists <none> beside other members" ;;
      esac
    fi

    case "$val" in
      ""|"null"|"~") invalid "$key is empty; run /wf-config to set it" ;;
      "<unset>") invalid "$key must not be set to <unset>; that marker means a key the file does not declare" ;;
      "<none>")
        case "$shape" in
          *.N) ;;
          *) invalid "$key must not be set to <none>; that marker means an empty list, and $key is a single value" ;;
        esac
        case "$key" in
          *.1) none_prefix="${key%.*}" ;;
          *) invalid "${key%.*} lists <none> beside other members" ;;
        esac ;;
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

# emit <kv>: print every key in KNOWN_SHAPES order, one line minimum each. A
# list the file set replaces whatever the template holds rather than appending,
# so a two-name roster means two cycles and not six.
emit() {
  local kv="$1" shape prefix line found n first oldifs hadf
  # One split instead of two forks per key. `set -f` is load-bearing: with IFS
  # at newline the whole `key=value` line is one word, so a value like
  # `grep -r * .` does not expand, but one that makes its line match a filename
  # would - `verify.commands: ["*"]` resolved beside a file named
  # `verify.commands.1=a` splits one dump line into two. The restore reads the
  # caller's flag rather than assuming it: sourced as a library (_WF_LIB_ONLY),
  # a bare `set +f` hands a caller that had globbing off a shell where it is on.
  case $- in
    *f*) hadf=yes ;;
    *) hadf=no ;;
  esac
  oldifs="$IFS"
  set -f; IFS='
'
  set -- $kv
  IFS="$oldifs"
  [ "$hadf" = yes ] || set +f

  for shape in "${KNOWN_SHAPES[@]}"; do
    case "$shape" in
      *.N)
        prefix="${shape%.N}"
        n=0; first=""
        for line in "$@"; do
          case "$line" in
            "$prefix".*)
              n=$((n + 1))
              if [ "$n" -eq 1 ]; then first="$line"; fi ;;
          esac
        done
        if [ "$n" -eq 0 ]; then
          printf '%s=<unset>\n' "$prefix"
        elif [ "$n" -eq 1 ] && [ "$first" = "$prefix.1=<none>" ]; then
          # validate has already rejected <none> beside other members, so a
          # sole <none> is exactly what `[]` produced and means the same thing.
          printf '%s=<none>\n' "$prefix"
        else
          for line in "$@"; do
            case "$line" in
              "$prefix".*) printf '%s\n' "$line" ;;
            esac
          done
        fi ;;
      *)
        found=""
        for line in "$@"; do
          case "$line" in
            "$shape"=*) found="$line" ;;
          esac
        done
        if [ -z "$found" ]; then
          printf '%s=<unset>\n' "$shape"
        else
          printf '%s\n' "$found"
        fi ;;
    esac
  done
}

# require <dump> <present> <csv>: halt on any named key the dump reports
# <unset>. The halt lives here rather than in five SKILL.md copies of the same
# thirteen lines: the message is one string, the comparison is not a judgment,
# and a skill already forks this script once.
#
# Naming a key the script does not know is a usage error, not a halt - it is a
# typo in the caller, and reporting it as "unset" would be a halt that no
# /wf-config run could ever clear.
require() {
  local dump="$1" present="$2" csv="$3" key missing="" seen="|" n=0 total=0 oldifs hadf
  # Same flag discipline as emit(): restore what the caller had rather than
  # assuming globbing was on.
  case $- in
    *f*) hadf=yes ;;
    *) hadf=no ;;
  esac
  oldifs="$IFS"; IFS=','
  set -f
  set -- $csv
  IFS="$oldifs"
  [ "$hadf" = yes ] || set +f
  for key in "$@"; do
    # Trimmed so a caller may write its list readably. A space after a comma is
    # the only separator a comma-delimited list invites by accident.
    while :; do case "$key" in [[:space:]]*) key="${key#?}" ;; *) break ;; esac; done
    while :; do case "$key" in *[[:space:]]) key="${key%?}" ;; *) break ;; esac; done
    [ -n "$key" ] || continue
    # One index dropped, never two. A skill names a list member
    # (`review.reviewers.1`) as readily as the list, and the dump's <unset> line
    # carries the bare key either way; `review.reviewers.1.2` is a spelling no
    # file can declare, so accepting it would match no dump line and halt on
    # nothing - the silent no-halt this die exists to prevent.
    case "${key##*.}" in
      ''|*[!0-9]*) ;;
      *) key="${key%.*}" ;;
    esac
    is_known_shape "$key" || is_known_shape "$key.N" \
      || die "--require names $key, which is not a key this script knows"
    # A key named twice - within one list, or across accumulated --require
    # flags - would be counted twice and named twice in the line below, and
    # pluralise a message about a single key.
    case "$seen" in
      *"|$key|"*) continue ;;
    esac
    seen="$seen$key|"
    total=$((total + 1))
    # Anchored on a leading newline so one key cannot match inside another's
    # line; the dump is newline-separated and every line starts with its key.
    case "
$dump" in
      *"
$key=<unset>"*)
        missing="$missing, $key"
        n=$((n + 1)) ;;
    esac
  done
  [ "$n" -gt 0 ] || return 0
  missing="${missing#, }"
  # Every named key unset AND no file at all is one condition with one cause,
  # and naming nine keys for it would bury the cause under its symptoms.
  if [ "$n" -eq "$total" ] && [ "$present" = no ]; then
    halt "No .wf.yml in this repo. Run /wf-config to create one."
  fi
  if [ "$n" -eq 1 ]; then
    halt "$missing is unset in .wf.yml. Run /wf-config to set it, then retry."
  fi
  halt "$missing are unset in .wf.yml. Run /wf-config to set them, then retry."
}

# resolve <root> <csv>: the whole decision. See the exit codes above.
resolve() {
  local root="$1" csv="$2" file kv dump present
  [ -d "$root" ] || die "no such directory: $root"
  file="$(config_path "$root")"
  if [ -z "$file" ]; then
    present=no
    dump="$(emit "")"
  else
    present=yes
    kv="$(read_props "$file")"
    validate "$kv"
    dump="$(emit "$kv")"
  fi
  # Before the dump, not after: a halted skill reads stderr and stops, and a
  # dump printed alongside the halt invites it to carry on with the rest.
  [ -z "$csv" ] || require "$dump" "$present" "$csv"
  printf '%s\n' "$dump"
}

main() {
  local repo_root="." require=""
  while [ $# -gt 0 ]; do
    case "$1" in
      --repo-root)
        # Emptiness matters as much as arity: an empty value would resolve the
        # working directory, which is not what an explicit flag asked for.
        { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--repo-root needs a value"
        repo_root="$2"; shift 2 ;;
      --require)
        { [ $# -ge 2 ] && [ -n "$2" ]; } || die "--require needs a value"
        # Repeats accumulate rather than replace, so a caller can build the
        # list up without the last flag silently winning.
        require="${require:+$require,}$2"; shift 2 ;;
      -h|--help)
        usage; exit 0 ;;
      *)
        usage >&2; die "unknown argument: $1" ;;
    esac
  done

  resolve "$repo_root" "$require"
}

# Sourced with _WF_LIB_ONLY=1 (by tests): define functions and stop before
# parsing args or reading a tree.
if [ -n "${_WF_LIB_ONLY:-}" ]; then
  return 0 2>/dev/null || exit 0
fi

main "$@"
