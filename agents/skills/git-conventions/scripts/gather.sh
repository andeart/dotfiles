#!/usr/bin/env bash
set -euo pipefail

# The commit-message gather: the porcelain status, the diff stat, and a -U1
# patch without lockfiles. suggest-commit runs this script, and stage-work.sh in
# wf-ship prints its output under `gather<<<`. No other file holds this command.
#
# Each flag makes the output independent of one user setting:
#   --untracked-files=normal   status.showUntrackedFiles=no removes new files
#   --no-color                 color.ui=always adds ESC bytes to a piped diff
#   --no-ext-diff              diff.external replaces the patch or fails
#   --no-relative              diff.relative removes paths outside the cwd
#   --submodule=short          diff.submodule=diff adds the submodule log
#   --ignore-submodules=dirty  diff.ignoreSubmodules=all removes a gitlink
#                              change; =none also scans each submodule worktree
#                              for changes that no commit here can hold
#   --no-textconv              a textconv driver changes the patch, and a
#                              git-crypt or transcrypt driver prints plaintext
# `top` binds the exclude pathspecs to the repo root. Without `top`, they bind
# to the cwd, and from a subdirectory the patch includes a root lockfile.

usage() {
  cat <<'EOF'
Usage: gather.sh

Takes no arguments. Prints the current repository's porcelain status, the diff
stat against HEAD, and the -U1 patch against HEAD without lockfiles. Where HEAD
does not resolve, both diffs are of the index (--cached).

Exit status:
  0  output is complete
  2  usage error
EOF
}

if [ "$#" -ne 0 ]; then
  usage >&2
  exit 2
fi

base=HEAD
git rev-parse --verify --quiet HEAD >/dev/null || base=--cached

git status --porcelain --untracked-files=normal --ignore-submodules=dirty
git diff "$base" --stat --no-color --no-ext-diff --no-textconv --no-relative \
  --submodule=short --ignore-submodules=dirty
git diff "$base" -U1 --no-color --no-ext-diff --no-textconv --no-relative \
  --submodule=short --ignore-submodules=dirty \
  -- ':(top,exclude)*.lock' ':(top,exclude)*-lock.json'
