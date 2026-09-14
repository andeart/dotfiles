#!/usr/bin/env bash
set -euo pipefail

# The commit-message gather: porcelain status, the diff stat, then a -U1 patch
# without lockfiles. suggest-commit runs it, and wf-ship's stage-work.sh prints
# its output under `gather<<<`. This is the only copy of the command.
#
# Each flag pins output that user config would otherwise change:
#   --untracked-files=normal  status.showUntrackedFiles=no drops new files
#   --no-color                color.ui=always puts ESC bytes in a piped diff
#   --no-ext-diff             diff.external replaces the patch, or fails it
#   --no-relative             diff.relative drops paths outside the cwd
#   --submodule=short         diff.submodule=diff inlines a submodule's log
#   --ignore-submodules=none  diff.ignoreSubmodules=all drops a gitlink change
#   --no-textconv             a textconv driver rewrites the patch, and a
#                             git-crypt or transcrypt one prints plaintext
# `top` binds the exclude-only pathspecs to the repo root. Without it they bind
# to the cwd, and from a subdirectory a root lockfile's patch comes through.

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

git status --porcelain --untracked-files=normal --ignore-submodules=none
git diff "$base" --stat --no-color --no-ext-diff --no-textconv --no-relative \
  --submodule=short --ignore-submodules=none
git diff "$base" -U1 --no-color --no-ext-diff --no-textconv --no-relative \
  --submodule=short --ignore-submodules=none \
  -- ':(top,exclude)*.lock' ':(top,exclude)*-lock.json'
