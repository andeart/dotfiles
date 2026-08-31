#!/usr/bin/env bash
# Sourced, not run: the shared 15s/60s poll cadence for await-auto-merge.sh and
# watch-post-merge-ci.sh. Kept as one function so tuning the cadence - C2 in
# DX-73's design unified it into one answer for the family - only ever touches
# one place instead of two copies that can drift apart.

# poll_sleep <start> <end>: sleep the family's cadence - 15s for the first two
# minutes of polling, then 60s - clamped to whatever is left of the window
# ($end - the current $SECONDS). Sleeps nothing once that remainder hits zero.
poll_sleep() {
  local start="$1" end="$2" iv rem
  if [ $((SECONDS - start)) -lt 120 ]; then iv=15; else iv=60; fi
  rem=$((end - SECONDS))
  [ "$iv" -gt "$rem" ] && iv=$rem
  [ "$iv" -gt 0 ] && sleep "$iv"
}
