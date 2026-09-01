#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

HELPER="$DOTFILES_ROOT/agents/skills/wf-wrap/scripts/poll-cadence.sh"

# Sourced by await-auto-merge.sh and watch-post-merge-ci.sh, never run on its
# own - this suite drives it through a small script that sources it, sets
# $SECONDS to a fixed value (SECONDS is otherwise a live, auto-incrementing
# bash builtin), and calls poll_sleep with the start/end it's asked to test.
setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_BIN"
  # Records the requested duration instead of actually sleeping, and prints
  # nothing when poll_sleep decides not to call it at all.
  cat > "$STUB_BIN/sleep" <<'EOF'
#!/bin/sh
printf 'slept=%s\n' "$1"
EOF
  chmod +x "$STUB_BIN/sleep"

  DRIVER="$BATS_TEST_TMPDIR/driver.sh"
  cat > "$DRIVER" <<EOF
#!/usr/bin/env bash
. "$HELPER"
SECONDS=\$1
poll_sleep "\$2" "\$3"
EOF
  chmod +x "$DRIVER"
}

run_driver() {
  run env PATH="$STUB_BIN:$PATH" "$DRIVER" "$@"
}

@test "sleeps 15s while within the first two minutes of polling" {
  run_driver 10 0 1000
  [ "$output" = "slept=15" ]
}

@test "the boundary at exactly two minutes of polling already uses the slower cadence" {
  run_driver 120 0 1000
  [ "$output" = "slept=60" ]
}

@test "sleeps 60s once two minutes of polling have passed" {
  run_driver 130 0 1000
  [ "$output" = "slept=60" ]
}

@test "clamps the interval to what remains of the window" {
  run_driver 500 0 505
  [ "$output" = "slept=5" ]
}

@test "sleeps nothing once the window has already elapsed" {
  run_driver 1000 0 1000
  [ -z "$output" ]
}

# The script's shebang resolves to bash 5.x on this machine's PATH, so a
# passing `bash -n` proves nothing about macOS's shipped /bin/bash 3.2 - only
# running the parser under 3.2 itself does. CI runs Ubuntu, where /bin/bash is
# already 5.x, so skip there rather than pass trivially.
@test "the helper parses under /bin/bash when that is bash 3.x" {
  local version
  version="$(/bin/bash --version | head -n1)"
  [[ "$version" == *"version 3."* ]] || skip "/bin/bash here is not 3.x: $version"
  run /bin/bash -n "$HELPER"
  [ "$status" -eq 0 ]
}
