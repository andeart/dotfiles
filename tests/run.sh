#!/usr/bin/env bash
# Runs the bats suite as one process per file under a bounded sliding window.
#
# Serial `bats tests/` takes 84s here; this takes 26s (measured 2026-08-30, 596
# tests, 12-core macOS). Wall clock is pinned by the longest single file, so the
# cap is not load-bearing: 6, 8 and 12 all land within 2s of each other, and
# ordering the files longest-first made no difference. Hence no bin-packing, no
# per-file duration table, and plain glob order.
#
# The window polls `jobs -rp` rather than using `wait -n`, which needs bash 4.3
# where this repo targets the 3.2 macOS ships. A chunked alternative that waits
# on a whole batch before starting the next measured worse (31s at cap 8),
# because the barrier idles cores behind each batch's longest file. Do not
# "tidy" either of these back.
#
# Running the files concurrently requires that no test reads or writes inside
# the repo working tree. AGENTS.md carries that as a rule.
set -uo pipefail

# The cap tracks the host, it is not hardcoded. A3 points this same script at
# pre-commit's bats hook, which also runs in CI on a GitHub-hosted runner with
# far fewer cores than the 12-core machine the timings above came from, where a
# cap sized for 12 would contend rather than parallelise.
#
# `_NPROCESSORS_ONLN` is the Solaris/glibc/BSD spelling; POSIX standardises the
# bare `NPROCESSORS_ONLN`. Both return the same value on macOS and on CI's
# Linux, so try each rather than betting on one. Anything unusable falls back to
# 1: slower is the right trade for an environment nobody measured, a crash is
# not.
CAP="$(getconf _NPROCESSORS_ONLN 2>/dev/null || getconf NPROCESSORS_ONLN 2>/dev/null || echo 1)"
case "$CAP" in
  ''|*[!0-9]*) CAP=1 ;;
esac
[ "$CAP" -ge 1 ] || CAP=1

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ "$#" -gt 0 ] && [ "$1" = "--list-only" ]; then
  for f in "$REPO_ROOT"/tests/*.bats; do
    printf '%s\n' "${f#"$REPO_ROOT"/}"
  done
  exit 0
fi

if [ "$#" -gt 0 ]; then
  files=("$@")
else
  files=("$REPO_ROOT"/tests/*.bats)
fi

# mktemp, never a fixed or predictable name: two overlapping invocations (a
# local run alongside a reviewer's verify.commands run in another worktree)
# must not collide. The trap fires on interrupt too, not just the happy path -
# this runs on every commit via A3 and inside every verify.commands call, so a
# Ctrl-C or a cancelled CI job would otherwise leave a directory behind on each
# attempt. A SIGKILL still slips past, but mktemp already makes that harmless.
outdir="$(mktemp -d)"
trap 'rm -rf "$outdir"' EXIT

for f in "${files[@]}"; do
  while [ "$(jobs -rp | wc -l)" -ge "$CAP" ]; do
    sleep 0.2
  done
  # The exit status is captured per file, not just the TAP output. A file that
  # crashes before emitting any TAP produces neither `ok` nor `not ok` lines,
  # and counting those alone would score it as a clean pass.
  ( bats "$f" > "$outdir/$(basename "$f").log" 2>&1; echo $? > "$outdir/$(basename "$f").status" ) &
done
wait

passed=0
failed=0
failing_files=""
for f in "${files[@]}"; do
  log="$outdir/$(basename "$f").log"
  p=$(grep -c '^ok ' "$log" 2>/dev/null || true)
  n=$(grep -c '^not ok' "$log" 2>/dev/null || true)
  st=$(cat "$outdir/$(basename "$f").status" 2>/dev/null || true)
  p=${p:-0}
  n=${n:-0}
  st=${st:-1}
  passed=$((passed + p))
  failed=$((failed + n))
  if [ "$n" -gt 0 ] || [ "$st" -ne 0 ]; then
    failing_files="$failing_files $f"
  fi
done

printf 'Total: %d passed, %d failed, across %d files\n' "$passed" "$failed" "${#files[@]}"

# The failing output goes last, deliberately. AGENTS.md forbids truncating a
# runner's output with `head` precisely because the part worth reading is the
# tail; that only stays true if the failures are the tail.
if [ -n "$failing_files" ]; then
  for f in $failing_files; do
    printf '\n=== %s ===\n' "$f"
    cat "$outdir/$(basename "$f").log"
  done
  exit 1
fi

exit 0
