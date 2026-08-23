#!/usr/bin/env bash
set -euo pipefail

# Decides whether a local branch that failed wf-prune's two merge criteria was
# superseded: its work landed on the default branch under a different branch
# name. Prints `key=value` evidence lines; exits 0 when superseded, 1 otherwise.
#
# Only ever widens what wf-prune lists. A branch reaching this probe is one both
# existing criteria already rejected.

# Reads a work item identifier off the front of a branch name.
# `worktree-` is stripped first: EnterWorktree prefixes the branches it creates.
wf_identifier_from_branch() {
  local name=${1#worktree-}
  printf '%s' "$name" \
    | sed -nE 's/^([A-Za-z]+)-([0-9]+)([^0-9].*)?$/\1-\2/p' \
    | tr '[:lower:]' '[:upper:]'
}

# Merged pull requests whose title starts with the identifier, as
# `number<TAB>mergeCommitOid`. Match the title here rather than handing the
# identifier to `gh --search`: that search also reads the body and tokenizes the
# identifier, so it returns pull requests for unrelated work items.
wf_merged_prs_for() {
  gh pr list --state merged --limit 200 --json number,title,mergeCommit \
    | jq -r --arg id "$1" '
        .[]
        | select(.title | test("^" + $id + "\\b"))
        | "\(.number)\t\(.mergeCommit.oid // "")"'
}

wf_pr_paths() {
  gh pr view "$1" --json files | jq -r '.files[].path'
}

wf_probe_branch() {
  local branch=$1 default=$2 id mb
  id=$(wf_identifier_from_branch "$branch")
  if [ -z "$id" ]; then
    printf 'verdict=excluded\nreason=no-identifier\n'
    return 1
  fi
  if ! mb=$(git merge-base "$default" "$branch" 2>/dev/null) || [ -z "$mb" ]; then
    printf 'verdict=excluded\nreason=no-merge-base\nidentifier=%s\n' "$id"
    return 1
  fi

  # Keep only PRs that landed strictly after the branch diverged. A PR whose
  # merge commit is missing locally is dropped rather than assumed: dropping can
  # only fail the coverage test below, which is the safe direction.
  local nums=() num oid
  while IFS=$'\t' read -r num oid; do
    [ -n "$num" ] && [ -n "$oid" ] || continue
    [ "$oid" != "$mb" ] || continue
    git cat-file -e "${oid}^{commit}" 2>/dev/null || continue
    git merge-base --is-ancestor "$mb" "$oid" 2>/dev/null || continue
    nums+=("$num")
  done < <(wf_merged_prs_for "$id")

  if [ ${#nums[@]} -eq 0 ]; then
    printf 'verdict=excluded\nreason=no-landed-pr\nidentifier=%s\n' "$id"
    return 1
  fi

  local union
  union=$(for num in "${nums[@]}"; do wf_pr_paths "$num"; done | sort -u)

  # Two things have to hold for every path the branch touched. It has to appear
  # in the union, and the default branch has to agree with the direction of the
  # change: a path the branch added or modified must exist there, and one the
  # branch deleted must not. Coverage alone cannot see the deletion case - the
  # path is in the PR's file list either way.
  local total=0 uncovered=0 wrong_direction=0 change path
  while IFS=$'\t' read -r change path; do
    [ -n "$path" ] || continue
    total=$((total + 1))
    if ! printf '%s\n' "$union" | grep -qxF -- "$path"; then
      uncovered=$((uncovered + 1))
    fi
    if [ "$change" = D ]; then
      if git cat-file -e "${default}:${path}" 2>/dev/null; then
        wrong_direction=$((wrong_direction + 1))
      fi
    elif ! git cat-file -e "${default}:${path}" 2>/dev/null; then
      wrong_direction=$((wrong_direction + 1))
    fi
  done < <(git diff --no-renames --name-status "$mb" "$branch")

  local prs
  prs=$(IFS=,; printf '%s' "${nums[*]}")

  if [ "$total" -eq 0 ] || [ "$uncovered" -gt 0 ]; then
    printf 'verdict=excluded\nreason=uncovered-paths\nidentifier=%s\nprs=%s\npaths=%s\nuncovered=%s\n' \
      "$id" "$prs" "$total" "$uncovered"
    return 1
  fi

  if [ "$wrong_direction" -gt 0 ]; then
    printf 'verdict=excluded\nreason=change-not-reflected\nidentifier=%s\nprs=%s\npaths=%s\nunreflected=%s\n' \
      "$id" "$prs" "$total" "$wrong_direction"
    return 1
  fi

  printf 'verdict=superseded\nidentifier=%s\nprs=%s\npaths=%s\n' "$id" "$prs" "$total"
}

wf_usage() {
  cat <<'EOF'
Usage: superseded-probe.sh <branch> <default-branch>

Decides whether <branch> - one that wf-prune's two merge criteria both rejected -
was superseded: its work landed on <default-branch> under a different branch name.
Writes `key=value` evidence to stdout.

Exit status:
  0  superseded
  1  not superseded
  2  usage error
EOF
}

if [ -n "${_WF_PRUNE_LIB_ONLY:-}" ]; then return 0; fi

case "${1:-}" in
  -h|--help) wf_usage; exit 0 ;;
esac

if [ "$#" -ne 2 ]; then
  wf_usage >&2
  exit 2
fi

wf_probe_branch "$1" "$2"
