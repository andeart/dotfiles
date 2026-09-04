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

# path <root>: run --print-config-path, keeping stdout and stderr apart. The
# flag and a resolve share config_path exactly, so the fixture cases below
# assert both inside one test rather than growing a parallel table to drift
# against.
path() {
  run --separate-stderr bash "$RESOLVE" --repo-root "$1" --print-config-path
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
  [[ "$output" == *"--print-config-path"* ]]
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

# Nested aliases expand multiplicatively, so this 289-byte document holds an
# unbounded `yq -o=props` past any wall clock at full CPU - no cap on size or
# depth reaches it. AGENTS.md requires a SKILL.md block to fit inside the Bash
# tool's timeout and six of them fork this script, so the bound is what makes
# that rule hold from underneath. A timeout reports separately from a parse
# failure: they need different fixes.
@test "an alias chain is killed at the deadline rather than parsed" {
  local root; root="$(repo alias-bomb)"
  config "$root" 'a: &a ["x","x","x","x","x","x","x","x","x"]
b: &b [*a,*a,*a,*a,*a,*a,*a,*a,*a]
c: &c [*b,*b,*b,*b,*b,*b,*b,*b,*b]
d: &d [*c,*c,*c,*c,*c,*c,*c,*c,*c]
e: &e [*d,*d,*d,*d,*d,*d,*d,*d,*d]
f: &f [*e,*e,*e,*e,*e,*e,*e,*e,*e]
g: &g [*f,*f,*f,*f,*f,*f,*f,*f,*f]
h: &h [*g,*g,*g,*g,*g,*g,*g,*g,*g]'
  run --separate-stderr env WF_YQ_TIMEOUT=1 bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"gave up parsing"* ]]
  [[ "$stderr" != *"could not parse"* ]]
}

@test "a non-numeric WF_YQ_TIMEOUT is a usage error" {
  local root; root="$(repo bad-timeout)"
  config "$root" 'states:
  shaping: Shaping'
  run --separate-stderr env WF_YQ_TIMEOUT=soon bash "$RESOLVE" --repo-root "$root"
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"whole number of seconds"* ]]
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
# One level in from the root-list case. Walking every trailing index off is
# what keeps yq's raw 0-based inner index out of the message, in a dump that
# promises 1-based indices everywhere else.
@test "a nested list names the list, not yq's inner index" {
  local root; root="$(repo nested-list)"
  config "$root" 'review:
  reviewers: [[], "A"]'
  resolve "$root"
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"review.reviewers must be a list of single values"* ]]
  [[ "$stderr" != *".0"* ]]
}

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

# The other half of the multi-document story, pinned because it is a decision
# rather than an oversight. Documents that share no key flatten into one
# well-formed dump - every key the file declares, exactly once, no value lost -
# so the resolver has nothing to reject and honours it. /wf-config stops on the
# same file, because there the merge would concatenate two mappings with no
# separator and the template's value would win over the user's. Rejecting it
# here as well was tried and dropped: every single-fork way of counting
# documents that yq offers breaks a behaviour this suite pins above, and a
# second fork would cost the one-yq-fork guarantee below for a file that is
# already resolved correctly.
@test "documents that share no key flatten into one dump" {
  local root; root="$(repo disjoint-docs)"
  config "$root" 'states:
  shaping: FromFirst
---
workspace:
  impl: worktree'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromFirst" ]
  [ "$(value workspace.impl)" = "worktree" ]
  [ "$(value states.implementing)" = "<unset>" ]
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
  # workspace.impl is an invariant here - work happens on plain feature
  # branches in this repo, never a worktree. The other values are preferences
  # the user is free to change, so pinning them would make a settings edit a
  # test edit.
  [ "$(value workspace.impl)" = "base" ]
}

# ─── the shipped template ──────────────────────────────────────────────────

# The template is the only place the shipped values live, so this is what stops
# a key reaching KNOWN_SHAPES without a matching template entry, and what pins
# the four reviewer names and four focus headings. An exit-0-and-no-<unset>
# assertion would not: it passes on a template whose reviewers were renamed.
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

# ─── --require ─────────────────────────────────────────────────────────────

# --require is the halt the five consuming skills used to spell out in thirteen
# lines of prose each. It is opt-in: a caller that names no key cannot reach
# exit 4, which is what lets /wf-wrap read a key without gaining a way to fail
# after its cleanup has already run.

FULL="states:
  shaping: Shaping
  implementing: Implementing
  in-review: In Review
workspace:
  impl: base
review:
  reviewers: [Ana]
  focus: [Speed]
ship:
  draft-by-default: true
verify:
  commands: [make test]
wrap:
  watch-post-merge-ci: false"

@test "--require is satisfied by a complete config" {
  local root; root="$(repo full)"
  config "$root" "$FULL"
  resolve "$root" --require states.shaping,workspace.impl
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
}

@test "--require still prints the whole dump when satisfied" {
  local root; root="$(repo dump)"
  config "$root" "$FULL"
  resolve "$root" --require states.shaping
  [ "$status" -eq 0 ]
  [ "$(value states.shaping)" = "Shaping" ]
  [ "$(value wrap.watch-post-merge-ci)" = "false" ]
}

@test "--require exits 4 naming the one key the file leaves out" {
  local root; root="$(repo one)"
  config "$root" "states:
  shaping: Shaping"
  resolve "$root" --require states.shaping,states.in-review
  [ "$status" -eq 4 ]
  [ "$stderr" = "states.in-review is unset in .wf.yml. Run /wf-config to set it, then retry." ]
}

# "them", not "it" - the message is read out verbatim by the skill that halted.
@test "--require names every missing key in one line, pluralised" {
  local root; root="$(repo many)"
  config "$root" "states:
  shaping: Shaping"
  resolve "$root" --require states.in-review,workspace.impl
  [ "$status" -eq 4 ]
  [ "$stderr" = "states.in-review, workspace.impl are unset in .wf.yml. Run /wf-config to set them, then retry." ]
}

# An absent file dumps every key <unset> exactly as an incomplete one does, so
# the collapse is what separates "fill these keys" from "there is no file".
@test "--require collapses to the absent-file message when there is no config" {
  local root; root="$(repo absent)"
  resolve "$root" --require states.shaping,states.in-review
  [ "$status" -eq 4 ]
  [ "$stderr" = "No .wf.yml in this repo. Run /wf-config to create one." ]
}

# The collapse is about the file, not the count: a present file missing every
# named key still names them, because /wf-config fills rather than creates.
@test "--require does not collapse when the file exists but lacks every named key" {
  local root; root="$(repo present)"
  config "$root" "states:
  shaping: Shaping"
  resolve "$root" --require workspace.impl
  [ "$status" -eq 4 ]
  [ "$stderr" = "workspace.impl is unset in .wf.yml. Run /wf-config to set it, then retry." ]
}

# <none> is a declared empty list. Halting on it would make `reviewers: []`
# impossible to state, which is the whole point of the marker.
@test "--require does not halt on a list the file declared empty" {
  local root; root="$(repo none)"
  config "$root" "review:
  reviewers: []"
  resolve "$root" --require review.reviewers
  [ "$status" -eq 0 ]
  [ "$(value review.reviewers)" = "<none>" ]
}

@test "--require accepts a list member spelling and reads it as the list" {
  local root; root="$(repo member)"
  config "$root" "review:
  reviewers: []"
  resolve "$root" --require review.reviewers.1
  [ "$status" -eq 0 ]
}

# A typo in a caller's key list is a usage error, not a halt: reported as unset
# it would be a halt that no /wf-config run could ever clear.
@test "--require rejects a key the script does not know as a usage error" {
  local root; root="$(repo typo)"
  config "$root" "$FULL"
  resolve "$root" --require states.in_review
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not a key this script knows"* ]]
}

@test "--require needs a value" {
  local root; root="$(repo noval)"
  run --separate-stderr bash "$RESOLVE" --repo-root "$root" --require
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"--require needs a value"* ]]
}

@test "repeated --require flags accumulate rather than replace" {
  local root; root="$(repo repeat)"
  config "$root" "states:
  shaping: Shaping"
  resolve "$root" --require states.shaping --require states.in-review
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"states.in-review is unset"* ]]
}

# Accumulating repeats is exactly what makes a duplicate reachable from a caller
# building its list up, so the dedupe is the other half of that feature.
@test "--require names a key once however many times it is given" {
  local root; root="$(repo dup-require)"
  config "$root" "workspace:
  impl: base"
  resolve "$root" --require states.shaping,states.shaping --require states.shaping
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"states.shaping is unset"* ]]
  [[ "$stderr" != *"states.shaping, states.shaping"* ]]
}

# One index is dropped, never two. `review.reviewers.1.2` is a spelling no file
# can declare, so it matches no dump line - accepting it would halt on nothing,
# which is the silent no-halt the usage error exists to prevent.
@test "--require rejects a doubly indexed key rather than halting on nothing" {
  local root; root="$(repo double-index)"
  config "$root" "workspace:
  impl: base"
  resolve "$root" --require review.reviewers.1.2
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"not a key this script knows"* ]]
}

@test "--require tolerates a space after a comma" {
  local root; root="$(repo spaced-require)"
  config "$root" "workspace:
  impl: base"
  resolve "$root" --require 'workspace.impl, states.shaping'
  [ "$status" -eq 4 ]
  [[ "$stderr" == *"states.shaping is unset"* ]]
}

# A broken config outranks an unset key: there is nothing to fill into a file
# that does not parse, and exit 3 names the fault the user has to fix first.
@test "a rejected config reports exit 3 even when --require names a missing key" {
  local root; root="$(repo broken)"
  config "$root" "bogus: 1"
  resolve "$root" --require states.shaping
  [ "$status" -eq 3 ]
  [[ "$stderr" == *"unknown key: bogus"* ]]
}

# ─── --print-config-path ───────────────────────────────────────────────────

@test "--print-config-path with --require is a usage error" {
  local root; root="$(repo print-and-require)"
  run --separate-stderr bash "$RESOLVE" --repo-root "$root" --print-config-path --require states.shaping
  [ "$status" -eq 2 ]
  [[ "$stderr" == *"cannot be combined with --require"* ]]
}

@test "--print-config-path with a nonexistent --repo-root exits 2" {
  run bash "$RESOLVE" --repo-root "$BATS_TEST_TMPDIR/absent" --print-config-path
  [ "$status" -eq 2 ]
}

# The flag's contract is that it answers before any yq work, which is a
# sentence in the design doc and nowhere else without this. The shim is the one
# the "read_props makes exactly one yq fork" case above builds, counting calls
# and delegating.
@test "--print-config-path forks no yq" {
  local root; root="$(repo print-no-fork)"
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
  run --separate-stderr env "PATH=$bin:$PATH" bash "$RESOLVE" \
    --repo-root "$root" --print-config-path
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$output" = "$root/.wf.yml" ]
  [ "$(wc -l < "$log" | tr -d ' ')" -eq 0 ]
}

# ─── a worktree's base clone ───────────────────────────────────────────────

# worktree <name>: build a linked worktree beside its base clone by hand and
# set $BASE, $WT and $REG. No git init, like every other fixture here: the code
# under test reads these two files and nothing else, so building them directly
# is both cheaper and closer to what is being tested.
#
# The two files are written differently on purpose, because git writes them
# differently: `gitdir: ` in front of the pointer, nothing in front of the
# back-reference. The trailing newline on both is load-bearing - without it
# `read` returns 1 with the value set, and a case pins an abort instead of the
# row it names.
worktree() {
  BASE="$BATS_TEST_TMPDIR/$1/base"
  WT="$BATS_TEST_TMPDIR/$1/wt"
  REG="$BASE/.git/worktrees/$1"
  mkdir -p "$REG" "$WT"
  printf 'gitdir: %s\n' "$REG" > "$WT/.git"
  printf '%s\n' "$WT/.git" > "$REG/gitdir"
}

# declines <root>: what every no-fallback row asserts. Exit 0 and an empty
# stderr, not merely an empty resolution: exit 1 is the shape this arm fails in
# - a declining branch that ends on a false test, or a read whose status `set
# -e` takes seriously - and a row checking only the dump would pass with a
# bound missing. The two unreadable rows below are what make the stderr half
# earn its place: they decline correctly and still print without the redirect.
declines() {
  resolve "$1"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "<unset>" ]
  path "$1"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ -z "$output" ]
}

@test "a worktree with its own .wf.yml reads its own" {
  worktree own
  config "$WT" 'states:
  shaping: FromWorktree'
  config "$BASE" 'states:
  shaping: FromBase'
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromWorktree" ]
  path "$WT"
  [ "$output" = "$WT/.wf.yml" ]
}

@test "a worktree with no .wf.yml reads the base clone's" {
  worktree inherit
  config "$BASE" 'states:
  shaping: FromBase
workspace:
  impl: worktree'
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  [ "$(value workspace.impl)" = "worktree" ]
  # One repo, one answer, whichever root it is read from. That is the whole
  # point of the arm, and an equality against the base clone's own dump says it
  # better than a key-by-key check.
  local inherited="$output"
  resolve "$BASE"
  [ "$output" = "$inherited" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

@test "a worktree whose base clone has no .wf.yml either inherits nothing" {
  worktree neither
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "<unset>" ]
  path "$WT"
  [ -z "$output" ]
}

@test "an ordinary clone whose .git is a directory resolves as before" {
  local root; root="$(repo ordinary)"
  mkdir -p "$root/.git"
  config "$root" 'states:
  shaping: FromRoot'
  resolve "$root"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromRoot" ]
  path "$root"
  [ "$output" = "$root/.wf.yml" ]
}

@test "a pointer shaped like a submodule does not fall back" {
  # `.git/modules/<name>`. The segment fails the shape test, and a submodule's
  # git dir carries no back-reference either.
  worktree submodule
  config "$BASE" 'states:
  shaping: FromBase'
  mkdir -p "$BASE/.git/modules/submodule"
  printf 'gitdir: %s/.git/modules/submodule\n' "$BASE" > "$WT/.git"
  declines "$WT"
}

@test "a pointer shaped like a bare repo under <name>.git does not fall back" {
  # `<name>.git/worktrees/<name>`: the segment is `repo.git`, so there is no
  # `/.git/` for the tail to match. The .wf.yml below sits where a wrong strip
  # would land, so the <unset> assertion is a real one.
  worktree bare-name
  local dir="$BATS_TEST_TMPDIR/bare-name"
  mkdir -p "$dir/repo.git/worktrees/w"
  printf 'gitdir: %s/repo.git/worktrees/w\n' "$dir" > "$WT/.git"
  printf '%s\n' "$WT/.git" > "$dir/repo.git/worktrees/w/gitdir"
  config "$dir" 'states:
  shaping: FromBareName'
  declines "$WT"
}

@test "a pointer under a bare repo kept at <dir>/.git falls back to <dir>" {
  # The `clone --bare <url> <dir>/.git` layout, which the shape test does not
  # separate out and needs no rule for: <dir> is the directory that owns the
  # worktree, so reading its .wf.yml is the right answer rather than an escape.
  # The bare markers below are inert to this script, which reads only the
  # registration's gitdir; they are here so the fixture says what it is.
  worktree bare-dir
  mkdir -p "$BASE/.git/objects" "$BASE/.git/refs"
  printf 'ref: refs/heads/main\n' > "$BASE/.git/HEAD"
  printf '[core]\n\tbare = true\n' > "$BASE/.git/config"
  config "$BASE" 'states:
  shaping: FromBareDir'
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBareDir" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

@test "a pointer ending in worktrees/ with no name does not fall back" {
  worktree no-name
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: %s/.git/worktrees/\n' "$BASE" > "$WT/.git"
  declines "$WT"
}

@test "a pointer whose base strips to nothing does not fall back" {
  # `gitdir: /.git/worktrees/x` leaves an empty base, which without the
  # non-empty clause would send the miss to `/.wf.yml` at the filesystem root
  # and print that path into a verify.commands disclosure. Nothing writable
  # sits there, so what declines this fixture in practice is the absent
  # back-reference one step earlier; the clause is the guard for the case a
  # writable registration directory would open, and it is unreachable from a
  # test by construction.
  worktree root-strip
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: /.git/worktrees/x\n' > "$WT/.git"
  declines "$WT"
}

@test "a .git file that is empty, malformed, or names a missing directory does not fall back" {
  worktree malformed
  config "$BASE" 'states:
  shaping: FromBase'
  : > "$WT/.git"
  declines "$WT"
  printf 'not a pointer\n' > "$WT/.git"
  declines "$WT"
  printf 'gitdir: %s/.git/worktrees/gone\n' "$BASE" > "$WT/.git"
  declines "$WT"
}

@test "a relative pointer resolves to the base clone" {
  worktree rel-pointer
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: ../base/.git/worktrees/rel-pointer\n' > "$WT/.git"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  # Printed exactly as base_clone built it: absolute, but carrying the `..` the
  # pointer spelled. It opens as written, and normalising it for display would
  # put a path normaliser in a script whose argument for -ef is that it needs
  # none.
  path "$WT"
  [ "$output" = "$WT/../base/.wf.yml" ]
}

@test "a relative back-reference resolves to the base clone" {
  worktree rel-backref
  config "$BASE" 'states:
  shaping: FromBase'
  # Four levels up from the registration is the fixture root; the kernel
  # resolves the `..` inside -ef, which is why nothing here normalises it.
  printf '%s\n' "../../../../wt/.git" > "$REG/gitdir"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

@test "a back-reference spelling root/.git through a symlink resolves to the base clone" {
  # This is what forces -ef over any hand-rolled normaliser: the relative case
  # above rules out string equality, but a normaliser collapsing `..`
  # textually passes that one and gets this wrong. -ef stats both paths.
  worktree symlinked
  config "$BASE" 'states:
  shaping: FromBase'
  ln -s "$WT" "$BATS_TEST_TMPDIR/symlinked/link"
  printf '%s\n' "$BATS_TEST_TMPDIR/symlinked/link/.git" > "$REG/gitdir"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

@test "a missing back-reference does not fall back" {
  worktree no-backref
  config "$BASE" 'states:
  shaping: FromBase'
  # Built by not writing the back-reference, pointing at a registration that
  # has none, rather than by removing one.
  mkdir -p "$BASE/.git/worktrees/absent"
  printf 'gitdir: %s/.git/worktrees/absent\n' "$BASE" > "$WT/.git"
  declines "$WT"
}

@test "a back-reference naming some other file does not fall back" {
  # A worktree copied out of someone else's clone, and a pointer left by a base
  # clone whose path was since reused, both arrive as this: the registration
  # still names the original worktree, not this one.
  worktree wrong-backref
  config "$BASE" 'states:
  shaping: FromBase'
  : > "$BASE/.git/config"
  printf '%s\n' "$BASE/.git/config" > "$REG/gitdir"
  declines "$WT"
}

@test "a back-reference that is a directory does not fall back" {
  # The observable proxy for a FIFO: the same [ -f ] declines both, and a FIFO
  # fixture would hang the suite rather than fail it if that guard were dropped.
  worktree dir-backref
  config "$BASE" 'states:
  shaping: FromBase'
  mkdir -p "$BASE/.git/worktrees/as-dir/gitdir"
  printf 'gitdir: %s/.git/worktrees/as-dir\n' "$BASE" > "$WT/.git"
  declines "$WT"
}

@test "a back-reference carrying a gitdir: prefix does not fall back" {
  # The back-reference is a bare path. The two files are read the same way and
  # parsed differently, and this is the row that says so: a prefixed value is
  # not the path, so it cannot match root/.git.
  worktree prefixed-backref
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: %s\n' "$WT/.git" > "$REG/gitdir"
  declines "$WT"
}

@test "an unreadable pointer does not fall back, and says nothing on stderr" {
  worktree unreadable-pointer
  config "$BASE" 'states:
  shaping: FromBase'
  chmod 000 "$WT/.git"
  declines "$WT"
}

@test "an unreadable back-reference does not fall back, and says nothing on stderr" {
  worktree unreadable-backref
  config "$BASE" 'states:
  shaping: FromBase'
  chmod 000 "$REG/gitdir"
  declines "$WT"
}

@test "a pointer file with no trailing newline resolves to the base clone" {
  # `read` returns 1 here with the value correctly set, which is why the arm
  # checks the value rather than the read's status.
  worktree no-newline
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: %s' "$REG" > "$WT/.git"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

@test "a pointer file with a second line resolves off the first" {
  # The read stops at the newline, which is what keeps a newline out of every
  # path this arm hands back - and therefore out of the wfconfig_path= line the
  # skills echo into a block of key=value lines. Swapping the capped read for
  # anything that slurps the file passes every other row here and fails this.
  worktree two-lines
  config "$BASE" 'states:
  shaping: FromBase'
  printf 'gitdir: %s\nsecond line\n' "$REG" > "$WT/.git"
  resolve "$WT"
  [ "$status" -eq 0 ]
  [ -z "$stderr" ]
  [ "$(value states.shaping)" = "FromBase" ]
  path "$WT"
  [ "$output" = "$BASE/.wf.yml" ]
}

# The only case here that does not use the script's entry point. No path a
# filesystem accepts reaches 4096 characters, so the cap is observable only by
# lowering the constant; a fixture big enough to separate a capped read from an
# uncapped one by wall clock is not an assertion tests/run.sh should carry
# while it runs its files concurrently. Both halves matter - the same fixture
# resolves at the real cap.
@test "a pointer longer than the cap is truncated and declines" {
  worktree capped
  call base_clone "$WT"
  [ "$status" -eq 0 ]
  [ "$output" = "$BASE" ]
  run bash -c '_WF_LIB_ONLY=1 source "$0"; POINTER_MAX=8; base_clone "$1"' \
    "$RESOLVE" "$WT"
  [ "$status" -eq 0 ]
  [ -z "$output" ]
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
