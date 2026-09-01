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

# Two files where the second can only pass if the runner waited for the first
# to fully exit before starting it. Under a cap of 1, `one.bats` (glob order
# puts it first) has to finish its own sleep and write its marker before
# `two.bats` is even launched; under an unenforced cap the runner would start
# both back to back, and `two.bats` would run its check well inside that
# window. This is what makes the two CPU-count-fallback cases below fail
# reliably rather than racily if the fallback breaks - not a timing guess.
make_serial_probe() {
  MARKERS="$BATS_TEST_TMPDIR/markers"
  mkdir -p "$MARKERS"
  cat > "$SUITE/tests/one.bats" <<EOF
@test "one" {
  sleep 0.3
  touch "$MARKERS/one-done"
}
EOF
  cat > "$SUITE/tests/two.bats" <<EOF
@test "two" {
  [ -e "$MARKERS/one-done" ]
}
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

# The case above only exercises --list-only's glob, not the one that decides
# what actually runs with no arguments. DOTFILES_TESTS_DIR repoints that real
# path at a fixture suite instead of this repo's own tests/ - pointing it at
# the real tests/ here would recurse into this very file.
@test "with no arguments it runs the selected suite, not just lists it" {
  make_suite
  pass_file alpha
  pass_file beta
  DOTFILES_TESTS_DIR="$SUITE/tests" run "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2 passed, 0 failed, across 2 files"* ]]
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

# bats still exits 0 and prints a `1..0` plan for a file with no @test blocks
# (the same shape a permission-denied file produces). Counting ok/not-ok lines
# and the exit status alone lets that through as a clean pass.
@test "a file whose plan is zero fails the run rather than scoring a clean pass" {
  make_suite
  pass_file alpha
  cat > "$SUITE/tests/empty.bats" <<'EOF'
#!/usr/bin/env bats
EOF
  run "$RUNNER" "$SUITE/tests/alpha.bats" "$SUITE/tests/empty.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"empty.bats"* ]]
  [[ "$output" == *"Total: 1 passed, 0 failed, across 2 files"* ]]
}

# The documented `tests/run.sh <file>...` interface accepts arbitrary paths, so
# two files sharing a basename in different directories must not collide on
# their log/status names.
@test "same-basename files in different directories don't collide" {
  make_suite
  mkdir -p "$SUITE/tests/a" "$SUITE/tests/b"
  cat > "$SUITE/tests/a/dup.bats" <<'EOF'
@test "passes" { true; }
EOF
  cat > "$SUITE/tests/b/dup.bats" <<'EOF'
@test "fails" { false; }
EOF
  run "$RUNNER" "$SUITE/tests/a/dup.bats" "$SUITE/tests/b/dup.bats"
  [ "$status" -ne 0 ]
  [[ "$output" == *"Total: 1 passed, 1 failed, across 2 files"* ]]
}

# ─── the CPU-count fallback ────────────────────────────────────────────────

# "Anything unusable falls back to 1: slower is the right trade for an
# environment nobody measured, a crash is not" - stated in the header comment,
# untested until now. Both cases below stub getconf to break in one of the
# two ways the runner guards against, then use make_serial_probe to prove the
# cap actually came out at 1 rather than merely not crashing.
@test "falls back to a cap of 1 when getconf itself is unusable" {
  make_suite
  make_serial_probe
  local stub_bin="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/getconf" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod +x "$stub_bin/getconf"
  DOTFILES_TESTS_DIR="$SUITE/tests" run env PATH="$stub_bin:$PATH" "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2 passed, 0 failed, across 2 files"* ]]
}

@test "falls back to a cap of 1 when getconf answers with something other than a bare number" {
  make_suite
  make_serial_probe
  local stub_bin="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$stub_bin"
  cat > "$stub_bin/getconf" <<'EOF'
#!/bin/sh
echo "undefined"
EOF
  chmod +x "$stub_bin/getconf"
  DOTFILES_TESTS_DIR="$SUITE/tests" run env PATH="$stub_bin:$PATH" "$RUNNER"
  [ "$status" -eq 0 ]
  [[ "$output" == *"Total: 2 passed, 0 failed, across 2 files"* ]]
}
