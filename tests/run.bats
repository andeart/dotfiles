#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

RUNNER="$DOTFILES_ROOT/tests/run.sh"

# A temp suite of fixture .bats files, so these cases never run the real suite.
make_suite() {
  SUITE="$(mktemp -d)"
  mkdir -p "$SUITE/tests"
}

pass_file() {
  cat > "$SUITE/tests/$1.bats" <<'EOF'
@test "passes" { true; }
EOF
}

fail_file() {
  cat > "$SUITE/tests/$1.bats" <<'EOF'
@test "fails" { false; }
EOF
}

@test "exits zero when every file passes" {
  make_suite
  pass_file alpha
  pass_file beta
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/beta.bats"
  [ "$status" -eq 0 ]
}

@test "exits non-zero when any file fails" {
  make_suite
  pass_file alpha
  fail_file beta
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/beta.bats"
  [ "$status" -ne 0 ]
}

@test "names the failing file, and names it after the summary" {
  make_suite
  pass_file alpha
  fail_file beta
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/beta.bats"
  [[ "$output" == *"beta.bats"* ]]
  # The failing output must come last: AGENTS.md forbids truncating a runner's
  # tail, which only holds if the tail is where the failures are.
  local summary_line failure_line
  summary_line=$(printf '%s\n' "$output" | grep -n "^Total" | tail -1 | cut -d: -f1)
  failure_line=$(printf '%s\n' "$output" | grep -n "not ok" | tail -1 | cut -d: -f1)
  [ "$failure_line" -gt "$summary_line" ]
}

@test "reports the total number of tests run across files" {
  make_suite
  pass_file alpha
  pass_file beta
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/beta.bats"
  [[ "$output" == *"Total: 2 passed"* ]]
}

@test "with no arguments it selects the repo's own suite directory" {
  run "$RUNNER" --list-only
  [ "$status" -eq 0 ]
  [ -n "$output" ]
  # Every listed path is a .bats file under tests/. Asserting on a specific
  # filename would break this case when an unrelated test file is renamed.
  while IFS= read -r line; do
    [[ "$line" == tests/*.bats ]]
  done <<< "$output"
}

# A file that crashes before bats emits any TAP produces neither `ok` nor
# `not ok` lines. Counting those alone would score it as a clean pass, so the
# runner reads each file's exit status too.
@test "a file that is not valid bats fails the run rather than scoring zero" {
  make_suite
  pass_file alpha
  printf 'this is not bats syntax {{{\n' > "$SUITE/tests/broken.bats"
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/broken.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"broken.bats"* ]]
}

# The runner ships in a repo that targets the bash 3.2 macOS still ships, so
# `wait -n` and friends are out. Parsing under 3.2 is the only thing that
# proves it; the shebang resolves to bash 5 on this machine's PATH.
@test "the runner parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$RUNNER"
  [ "$status" -eq 0 ]
}
