#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RESOLVE="$DOTFILES_ROOT/agents/skills/wf-conventions/scripts/resolve-wf-config.sh"

# Source the script in library mode inside a subshell (so its `set -euo
# pipefail` is contained) and invoke one function with args.
#   call <fn> [args...]
call() {
  run bash -c '_WF_LIB_ONLY=1 source "$0"; "$@"' "$RESOLVE" "$@"
}

# repo <name>: create a fixture repo root under the test tmpdir and print it.
# No git init - resolution reads the filesystem, not the index.
repo() {
  local root="$BATS_TEST_TMPDIR/$1"
  mkdir -p "$root"
  printf '%s\n' "$root"
}

# config <root> <body>: write .wf.yml at the repo root.
config() {
  printf '%s\n' "$2" > "$1/.wf.yml"
}

# resolve <root> [args...]: run the script, keeping stdout and stderr apart so
# assertions read the answer rather than the explanation.
resolve() {
  local root="$1"; shift
  run --separate-stderr bash "$RESOLVE" --repo-root "$root" "$@"
}

# value <key>: print the resolved value for one key from $output.
value() {
  printf '%s\n' "$output" | awk -v k="$1=" 'index($0, k) == 1 { print substr($0, length(k) + 1) }'
}

# ─── flags & usage ─────────────────────────────────────────────────────────

@test "--help prints usage and exits 0" {
  run bash "$RESOLVE" --help
  [ "$status" -eq 0 ]
  [[ "$output" == *"Usage: resolve-wf-config.sh"* ]]
}

@test "an unknown flag exits 2" {
  run bash "$RESOLVE" --nope
  [ "$status" -eq 2 ]
}

@test "--repo-root with no value exits 2" {
  run bash "$RESOLVE" --repo-root
  [ "$status" -eq 2 ]
}

@test "--repo-root with an empty value exits 2" {
  run bash "$RESOLVE" --repo-root ""
  [ "$status" -eq 2 ]
}

@test "a nonexistent --repo-root exits 2" {
  run bash "$RESOLVE" --repo-root "$BATS_TEST_TMPDIR/absent"
  [ "$status" -eq 2 ]
}

# ─── no config at all ──────────────────────────────────────────────────────

@test "a repo with no .wf.yml resolves every key to <unset>" {
  local root; root="$(repo bare)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "<unset>" ]
  [ "$(value states.implementing)" = "<unset>" ]
  [ "$(value states.in-review)" = "<unset>" ]
  [ "$(value workspace.impl)" = "<unset>" ]
  [ "$(value ship.draft-by-default)" = "<unset>" ]
  [ "$(value wrap.watch-post-merge-ci)" = "<unset>" ]
}

# The one key that never had a default now has the same shape as every other:
# undeclared is <unset>, and an explicit [] is <none>. The two are different
# answers, and only the second is one a skill acts on.
@test "an undeclared verify.commands is <unset>, not <none>" {
  local root; root="$(repo bare-tests)"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value verify.commands)" = "<unset>" ]
}

# The rename in DX-73. A repo still carrying the old name gets told the new one
# rather than a bare "unknown key", because the resolver's error is the only
# thing that will reach whoever is confused.
@test "the old ship.test-commands name names its replacement" {
  local root; root="$(repo renamed)"
  config "$root" 'ship:
  test-commands:
    - bats tests/'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"verify.commands"* ]]
}

# Deliberate divergence from resolve-tracker.sh, which falls back to tmp/ for
# public repos where a root-level tracker config would look out of place.
# Nothing in .wf.yml wants hiding, so the fallback would only add a place to
# look when a setting appears not to apply.
@test "tmp/.wf.yml is not read" {
  local root; root="$(repo tmp-only)"
  mkdir -p "$root/tmp"
  printf 'states:\n  shaping: FromTmp\n' > "$root/tmp/.wf.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "<unset>" ]
}

# ─── library mode ──────────────────────────────────────────────────────────

@test "library mode defines functions without resolving anything" {
  call is_known_shape states.shaping
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# shape_of writes SHAPE instead of printing: the command substitution was the
# cost, not the sed. Read it immediately after the call - it holds the previous
# call's value until then.
@test "shape_of replaces a trailing list index with N" {
  run bash -c '_WF_LIB_ONLY=1 source "$0"; shape_of "$1"; printf "%s\n" "$SHAPE"' \
    "$RESOLVE" review.reviewers.3
  [ "$status" -eq 0 ]
  [ "$output" = "review.reviewers.N" ]
}

@test "config_path prints nothing when there is no .wf.yml" {
  local root; root="$(repo no-config)"
  call config_path "$root"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

# ─── reading a config ──────────────────────────────────────────────────────

@test "a scalar in the file resolves to its value" {
  local root; root="$(repo scalar-override)"
  config "$root" 'states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Designing" ]
}

@test "keys the file leaves out resolve to <unset>" {
  local root; root="$(repo partial)"
  config "$root" 'states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.implementing)" = "<unset>" ]
  [ "$(value workspace.impl)" = "<unset>" ]
}

@test "a value containing spaces survives intact" {
  local root; root="$(repo spacey)"
  config "$root" 'states:
  in-review: Waiting On Review'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.in-review)" = "Waiting On Review" ]
}

# yq props uses " = " as its separator, so splitting on every occurrence would
# truncate any command carrying a flag assignment.
@test "a value containing an equals sign survives intact" {
  local root; root="$(repo equals)"
  config "$root" 'verify:
  commands:
    - make TARGET=all test'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value verify.commands.1)" = "make TARGET=all test" ]
}

# yq -o=props emits a comment as its own output line, unparsed. One containing
# " = " - a documented example, an inline aside - must not be mistaken for a
# key.
@test "an inline comment containing an equals sign does not break parsing" {
  local root; root="$(repo commented)"
  config "$root" 'workspace:
  impl: base   # spelled impl = base'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value workspace.impl)" = "base" ]
}

@test "a block sequence parses" {
  local root; root="$(repo block-list)"
  config "$root" 'review:
  reviewers:
    - Ana
    - Bo'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Ana" ]
  [ "$(value review.reviewers.2)" = "Bo" ]
}

# yq normalises both list syntaxes, so accepting each costs nothing and
# rejecting one would be a rule with no reason behind it.
@test "an inline sequence parses the same way" {
  local root; root="$(repo inline-list)"
  config "$root" 'review:
  reviewers: [Ana, Bo]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.1)" = "Ana" ]
  [ "$(value review.reviewers.2)" = "Bo" ]
}

# Merging against anything would mean a two-name roster silently ran six cycles.
@test "a list in the file is the whole list" {
  local root; root="$(repo list-replace)"
  config "$root" 'review:
  reviewers: [Ana, Bo]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers.2)" = "Bo" ]
  [ -z "$(value review.reviewers.3)" ]
}

@test "list indices in the dump are 1-based" {
  local root; root="$(repo one-based)"
  config "$root" 'review:
  reviewers: [Ana]'
  resolve "$root"
  [ "$status" -eq 0 ]
  [[ "$output" == *"review.reviewers.1=Ana"* ]]
  [[ "$output" != *"review.reviewers.0="* ]]
}

@test "an empty .wf.yml resolves every key to <unset>" {
  local root; root="$(repo empty-file)"
  : > "$root/.wf.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "<unset>" ]
  [ "$(value review.reviewers)" = "<unset>" ]
}

# An empty map is the one shape the sentinel rewrite does not reach, so a
# section written `{}` reads exactly like an absent one.
@test "an empty section leaves its keys <unset>" {
  local root; root="$(repo empty-section)"
  config "$root" 'review: {}'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers)" = "<unset>" ]
}

# The dump is an interface: a skill reads it and bats asserts on it, so the
# order must not depend on how the file happened to be written.
@test "output order is canonical regardless of the file's own order" {
  local root; root="$(repo ordering)"
  config "$root" 'wrap:
  watch-post-merge-ci: true
states:
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 0 ]
  local first last
  first="$(printf '%s\n' "$output" | head -1)"
  last="$(printf '%s\n' "$output" | tail -1)"
  [ "$first" = "states.shaping=Designing" ]
  [ "$last" = "wrap.watch-post-merge-ci=true" ]
}

# The two-line check above pins the ends; this pins the whole dump, so a
# reordering inside KNOWN_SHAPES fails a test instead of shipping unnoticed.
# Nine keys, nine lines: every key emits one even when the file is absent.
@test "the no-config dump matches KNOWN_SHAPES order exactly" {
  local root; root="$(repo full-dump)"
  resolve "$root"
  [ "$status" -eq 0 ]
  local expected
  expected="$(cat <<'EOF'
states.shaping=<unset>
states.implementing=<unset>
states.in-review=<unset>
workspace.impl=<unset>
review.reviewers=<unset>
review.focus=<unset>
ship.draft-by-default=<unset>
verify.commands=<unset>
wrap.watch-post-merge-ci=<unset>
EOF
)"
  [ "$output" = "$expected" ]
}

# yq -o=props drops an empty sequence entirely, so `[]` and an absent key are
# indistinguishable at the props layer. read_props rewrites every empty
# sequence to a one-member sentinel before the conversion; this is what pins
# that the two stay different answers.
@test "an empty list resolves to <none> on every list key" {
  local root; root="$(repo empty-lists)"
  config "$root" 'review:
  reviewers: []
  focus: []
verify:
  commands: []'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers)" = "<none>" ]
  [ "$(value review.focus)" = "<none>" ]
  [ "$(value verify.commands)" = "<none>" ]
  [ -z "$(value review.reviewers.1)" ]
}

# ─── validation ────────────────────────────────────────────────────────────

# read_props's `|| invalid` path: exit 3 depends on yq's own exit code here,
# not on validate().
@test "malformed YAML exits 3" {
  local root; root="$(repo malformed)"
  config "$root" 'states: [unterminated
  shaping: Designing'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"could not parse"* ]]
}

# Silently ignoring a key means a setting that appears to apply and does not,
# which is worse than a file that will not load.
@test "an unknown top-level section exits 3 and names it" {
  local root; root="$(repo unknown-section)"
  config "$root" 'bogus:
  thing: 1'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: bogus.thing"* ]]
  # validate() rejects through a heredoc, not a pipe, precisely so a rejection
  # never leaves a dump on stdout behind it.
  [ -z "$output" ]
}

@test "an unknown key inside a known section exits 3 and names it" {
  local root; root="$(repo unknown-key)"
  config "$root" 'ship:
  draft-by-defualt: true'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: ship.draft-by-defualt"* ]]
}

# The bare "unknown key" would send the reader hunting for a typo that is not
# there, so the shape mismatch says which of the two it is.
@test "a scalar where a list belongs says so" {
  local root; root="$(repo scalar-for-list)"
  config "$root" 'review:
  reviewers: Ana'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers must be a list"* ]]
}

@test "a list where a scalar belongs says so" {
  local root; root="$(repo list-for-scalar)"
  config "$root" 'workspace:
  impl: [base]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"workspace.impl must be a single value"* ]]
}

# A key written with no value reads as deliberate, so resolving it as a value
# would quietly do something other than what the file says.
@test "a key present with an empty value exits 3" {
  local root; root="$(repo empty-value)"
  config "$root" 'states:
  shaping:'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

# yq hands `null` and `~` through as literal strings, so the bare-key check
# alone would let two of YAML's three spellings of "no value" resolve as if
# they were the value.
@test "a key set to null exits 3" {
  local root; root="$(repo null-value)"
  config "$root" 'states:
  shaping: null'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

@test "a key set to a tilde exits 3" {
  local root; root="$(repo tilde-value)"
  config "$root" 'states:
  shaping: ~'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping is empty"* ]]
}

@test "an out-of-range workspace.impl exits 3 and lists the choices" {
  local root; root="$(repo bad-enum)"
  config "$root" 'workspace:
  impl: sandbox'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"workspace.impl must be base or worktree"* ]]
}

@test "workspace.impl accepts worktree" {
  local root; root="$(repo good-enum)"
  config "$root" 'workspace:
  impl: worktree'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value workspace.impl)" = "worktree" ]
}

@test "a non-boolean ship.draft-by-default exits 3" {
  local root; root="$(repo bad-bool)"
  config "$root" 'ship:
  draft-by-default: yes'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"ship.draft-by-default must be true or false"* ]]
}

@test "a non-boolean wrap.watch-post-merge-ci exits 3" {
  local root; root="$(repo bad-bool-wrap)"
  config "$root" 'wrap:
  watch-post-merge-ci: 1'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"wrap.watch-post-merge-ci must be true or false"* ]]
}

@test "a valid config passes validation and resolves" {
  local root; root="$(repo valid)"
  config "$root" 'workspace:
  impl: worktree
ship:
  draft-by-default: false
verify:
  commands:
    - bats tests/'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(value ship.draft-by-default)" = "false" ]
  [ "$(value verify.commands.1)" = "bats tests/" ]
}

# The markers are in-band, so nothing legitimate may produce one. <unset> means
# a key the file never declared; a file that writes it is claiming a state it
# cannot be in.
@test "a scalar set to <unset> exits 3" {
  local root; root="$(repo unset-scalar)"
  config "$root" 'states:
  shaping: <unset>'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping"* ]]
}

@test "a scalar set to <none> exits 3" {
  local root; root="$(repo none-scalar)"
  config "$root" 'states:
  shaping: <none>'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping"* ]]
}

@test "a list member set to <unset> exits 3" {
  local root; root="$(repo unset-member)"
  config "$root" 'review:
  reviewers: [Ana, "<unset>"]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers"* ]]
}

# <none> beside other members would reach /wf-ship's checks step as a command.
# The sole-member case is exactly what [] produces and is the legitimate one.
@test "a list carrying <none> beside other members exits 3" {
  local root; root="$(repo none-beside)"
  config "$root" 'review:
  reviewers: [Ana, "<none>"]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers"* ]]
}

@test "a list whose first member is <none> beside another exits 3" {
  local root; root="$(repo none-first)"
  config "$root" 'review:
  reviewers: ["<none>", Ana]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers"* ]]
}

# The markers only mean anything while no value can forge a dump line. This
# guards a property of yq's output format rather than of this script, so
# nothing here would catch it changing.
@test "a value carrying a newline emits exactly one dump line" {
  local root; root="$(repo newline-dq)"
  config "$root" 'states:
  shaping: "A\nwrap.watch-post-merge-ci=true"'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 9 ]
  [ "$(value wrap.watch-post-merge-ci)" = "<unset>" ]
}

@test "a block scalar carrying a newline emits exactly one dump line" {
  local root; root="$(repo newline-block)"
  config "$root" 'states:
  shaping: |-
    A
    wrap.watch-post-merge-ci=true'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | wc -l | tr -d ' ')" -eq 9 ]
  [ "$(value wrap.watch-post-merge-ci)" = "<unset>" ]
}

# The other forgery path, and this one is ours rather than yq's: emit splits on
# newline, so a value that makes its whole line match a filename would expand
# into two lines without `set -f`. The newline cases above stay green if it is
# removed; this one does not.
@test "a list value of * emits exactly the members the file declared" {
  local root; root="$(repo star)"
  config "$root" 'verify:
  commands: ["*"]'
  local world="$BATS_TEST_TMPDIR/star-cwd"
  mkdir -p "$world"
  : > "$world/verify.commands.1=a"
  : > "$world/verify.commands.1=b"
  run --separate-stderr bash -c 'cd "$1" || exit 1; bash "$2" --repo-root "$3"' \
    _ "$world" "$RESOLVE" "$root"
  [ "$status" -eq 0 ]
  [ "$(printf '%s\n' "$output" | awk '/^verify[.]commands[.]/' | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(value verify.commands.1)" = "*" ]
}

# Both resolved at exit 0 before the sentinel rewrite: `bogus: []` escaped the
# unknown-key rejection entirely, and a scalar written as an empty list took a
# default. The rewrite gives each a line, and validate rejects it.
@test "an unknown key written as an empty list names the key, not its index" {
  local root; root="$(repo bogus-empty-list)"
  config "$root" 'bogus: []'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: bogus"* ]]
  [[ "$stderr" != *"bogus.1"* ]]
}

@test "a scalar key written as an empty list says it must be a single value" {
  local root; root="$(repo impl-empty-list)"
  config "$root" 'workspace:
  impl: []'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"workspace.impl must be a single value"* ]]
}

# yq collapses duplicate keys inside one document, so a multi-document file is
# the only way to put a second `key=` line in front of the skill-side check -
# and it also breaks the rule that a list replaces rather than appends.
@test "a key set in two documents exits 3 and names it" {
  local root; root="$(repo two-docs)"
  config "$root" 'states:
  shaping: A
---
states:
  shaping: B'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"states.shaping"* ]]
}

# The script's header claims one yq fork per run and points here. A shim first
# on PATH counts the calls and delegates, which makes the claim an assertion.
@test "read_props makes exactly one yq fork" {
  local root; root="$(repo one-fork)"
  config "$root" 'states:
  shaping: Designing'
  local bin="$BATS_TEST_TMPDIR/bin" log="$BATS_TEST_TMPDIR/yq-calls" real
  real="$(command -v yq)"
  mkdir -p "$bin"
  cat > "$bin/yq" <<EOF
#!/usr/bin/env bash
echo call >> "$log"
exec "$real" "\$@"
EOF
  chmod +x "$bin/yq"
  : > "$log"
  run --separate-stderr env "PATH=$bin:$PATH" bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 1 ]
}

# ─── this repo's own config ────────────────────────────────────────────────

# The resolver's rejection paths are only useful if the file they guard is
# actually valid, and this is the one .wf.yml that ships in the repo. The
# no-<unset> assertion is what pins this repo against shipping a config that
# halts its own skills.
@test "the repo's own .wf.yml resolves cleanly" {
  run --separate-stderr bash "$RESOLVE" --repo-root "$DOTFILES_ROOT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [[ "$output" != *"<unset>"* ]]
  [ "$(value workspace.impl)" = "base" ]
  [ "$(value wrap.watch-post-merge-ci)" = "true" ]
}

# ─── the shipped template ──────────────────────────────────────────────────

# The template is the only place the shipped values live now that DEFAULTS is
# gone, so this is what stops a key reaching KNOWN_SHAPES without a matching
# template entry - and it is what carries the four reviewer names and four
# focus headings the two deleted default cases used to assert. An
# exit-0-and-no-<unset> assertion would not: it passes on a template whose
# reviewers were renamed.
@test "the shipped template round-trips to a complete dump" {
  local root; root="$(repo template)"
  cp "$DOTFILES_ROOT/agents/skills/wf-conventions/wf.yml.template" "$root/.wf.yml"
  resolve "$root"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  local expected
  expected="$(cat <<'EOF'
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
verify.commands=<none>
wrap.watch-post-merge-ci=false
EOF
)"
  [ "$output" = "$expected" ]
}

# ─── bash 3.2 compatibility ────────────────────────────────────────────────

# The script's shebang resolves to bash 5.x on this machine's PATH, so a
# passing `bash -n` above proves nothing about macOS's shipped /bin/bash 3.2 -
# only running the parser under 3.2 itself does. CI runs Ubuntu, where
# /bin/bash is already 5.x, so skip there rather than pass trivially.
@test "the script parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$RESOLVE"
  [ "$status" -eq 0 ]
}
