#!/usr/bin/env bash
# Measures which skill the model dispatches to for a given phrase.
#
# Each probe is a fresh non-interactive session granted only the Skill tool, with
# --strict-mcp-config and no --mcp-config so no MCP server is reachable. A probe that
# triggers file-work-item therefore cannot reach a tracker to create anything.
#
# Skills load from the repo via --plugin-dir rather than from ~/.agents, so this grades
# the working tree instead of whatever was last deployed. --setting-sources omits `user`
# to stop the deployed copies loading a second time under bare names.
set -euo pipefail

SUITE_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SUITE_DIR/../.." && pwd)
PLUGIN_DIR="$REPO_ROOT/agents"
CASES_FILE="$SUITE_DIR/cases.tsv"

# Re-entry for a single probe, dispatched by the batch loop below. Kept ahead of option
# parsing so the sentinel is never read as a flag.
if [ "${1:-}" = "__probe__" ]; then
  probe_prompt=$2
  probe_cwd=$3
  out=$(cd "$probe_cwd" && claude -p "$probe_prompt" \
    --output-format stream-json --verbose \
    --plugin-dir "$PLUGIN_DIR" \
    --setting-sources project,local \
    --strict-mcp-config \
    --allowedTools Skill 2>&1) || true
  actual=$(printf '%s' "$out" | grep -oE '"skill":"[^"]+"' | head -1 | sed 's/.*:"//; s/"$//')
  actual=${actual#agents:}
  [ -n "$actual" ] || actual='(none)'
  printf '%s\n' "$actual"
  exit 0
fi

RUNS=5
JOBS=5
CASE_GLOB='*'
OUT_DIR=""

usage() {
  cat <<'EOF'
Usage: run-triggers.sh [options]

  --runs <n>       Probes per case (default: 5)
  --jobs <n>       Concurrent probes (default: 5)
  --case <glob>    Only cases whose id matches this glob (default: all)
  --out-dir <dir>  Where results land (default: a timestamped dir under $TMPDIR)
  --help           This message

Exits 1 if any selected case scores below 1.0.
EOF
}

while [ $# -gt 0 ]; do
  case "$1" in
    --runs) [ $# -ge 2 ] || { echo "--runs needs a value" >&2; exit 2; }; RUNS=$2; shift 2 ;;
    --jobs) [ $# -ge 2 ] || { echo "--jobs needs a value" >&2; exit 2; }; JOBS=$2; shift 2 ;;
    --case) [ $# -ge 2 ] || { echo "--case needs a value" >&2; exit 2; }; CASE_GLOB=$2; shift 2 ;;
    --out-dir) [ $# -ge 2 ] || { echo "--out-dir needs a value" >&2; exit 2; }; OUT_DIR=$2; shift 2 ;;
    --help) usage; exit 0 ;;
    *) echo "unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

case "$RUNS" in ''|*[!0-9]*) echo "--runs must be a positive integer" >&2; exit 2 ;; esac
case "$JOBS" in ''|*[!0-9]*) echo "--jobs must be a positive integer" >&2; exit 2 ;; esac
[ "$RUNS" -gt 0 ] && [ "$JOBS" -gt 0 ] || { echo "--runs and --jobs must be positive" >&2; exit 2; }

command -v claude >/dev/null 2>&1 || { echo "claude is not on PATH" >&2; exit 2; }
[ -f "$CASES_FILE" ] || { echo "no cases file at $CASES_FILE" >&2; exit 2; }

[ -n "$OUT_DIR" ] || OUT_DIR="${TMPDIR:-/tmp}/skill-trigger-evals/$(date +%Y%m%d-%H%M%S)"
probes_dir="$OUT_DIR/probes"
# Probes run here rather than in the repo, so a triggered skill finds no tracker config.
probe_cwd="$OUT_DIR/cwd"
mkdir -p "$probes_dir" "$probe_cwd"
raw="$OUT_DIR/raw.tsv"

selected=0
jobs_file="$OUT_DIR/jobs.tsv"
: > "$jobs_file"
while IFS=$'\t' read -r id expected prompt; do
  case "$id" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2254
  case "$id" in $CASE_GLOB) ;; *) continue ;; esac
  selected=$((selected + 1))
  run=1
  while [ "$run" -le "$RUNS" ]; do
    printf '%s\t%s\t%s\t%s\n' "$id" "$run" "$expected" "$prompt" >> "$jobs_file"
    run=$((run + 1))
  done
done < "$CASES_FILE"

[ "$selected" -gt 0 ] || { echo "no cases matched --case $CASE_GLOB" >&2; exit 2; }

total=$((selected * RUNS))
echo "running $total probes across $selected cases at --runs $RUNS, --jobs $JOBS"
echo "results: $OUT_DIR"

# Fixed-size batches rather than `wait -n`, which needs bash 4.3 and macOS ships 3.2.
in_flight=0
while IFS=$'\t' read -r id run expected prompt; do
  "$SUITE_DIR/run-triggers.sh" __probe__ "$prompt" "$probe_cwd" > "$probes_dir/$id.$run" &
  in_flight=$((in_flight + 1))
  if [ "$in_flight" -ge "$JOBS" ]; then
    wait
    in_flight=0
    printf '.'
  fi
done < "$jobs_file"
wait
echo

: > "$raw"
while IFS=$'\t' read -r id run expected prompt; do
  actual=$(cat "$probes_dir/$id.$run" 2>/dev/null || echo '(none)')
  printf '%s\t%s\t%s\t%s\n' "$id" "$run" "$expected" "$actual" >> "$raw"
done < "$jobs_file"

echo
printf '%-28s %-26s %6s  %s\n' CASE EXPECTED SCORE ACTUALS
failed=0
while IFS=$'\t' read -r id expected prompt; do
  case "$id" in ''|\#*) continue ;; esac
  # shellcheck disable=SC2254
  case "$id" in $CASE_GLOB) ;; *) continue ;; esac
  hits=$(awk -F'\t' -v i="$id" -v e="$expected" '$1==i && $4==e' "$raw" | wc -l | tr -d ' ')
  seen=$(awk -F'\t' -v i="$id" '$1==i' "$raw" | wc -l | tr -d ' ')
  actuals=$(awk -F'\t' -v i="$id" '$1==i {print $4}' "$raw" | sort | uniq -c | sort -rn \
    | awk '{printf "%s%s x%s", (NR>1 ? ", " : ""), $2, $1}')
  score=$(awk -v h="$hits" -v s="$seen" 'BEGIN { printf "%.2f", (s ? h/s : 0) }')
  printf '%-28s %-26s %6s  %s\n' "$id" "$expected" "$score" "$actuals"
  if [ "$seen" -eq 0 ] || [ "$hits" -ne "$seen" ]; then
    failed=$((failed + 1))
  fi
done < "$CASES_FILE"

echo
if [ "$failed" -gt 0 ]; then
  echo "$failed of $selected cases scored below 1.0"
  exit 1
fi
echo "all $selected cases scored 1.0"
