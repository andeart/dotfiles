#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"

# The staging block is read out of SKILL.md rather than copied here. The skill
# is the only place it exists - nothing executes that file - so a copy would
# grade a stale expression and pass while the real one rotted, which is the
# same reason tests/wf-wrap-gh-jq.bats extracts wf-wrap's jq program instead of
# retyping it.
#
# Every case below grades what the index and the working tree hold after the
# block ran, not what the block printed about them. A test that read a
# classifier's stdout would pass on a correctly worded skill that stages the
# wrong files.

# ─── extraction ────────────────────────────────────────────────────────────

# The one fenced bash block inside "## Staging what belongs to the work".
# `^## ` closes the section without closing on `### Reporting the residue`,
# which is nested under it.
staging_block() {
  awk '
    /^## Staging what belongs to the work$/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^```bash$/ { fence = 1; next }
    insec && fence && /^```$/ { fence = 0; next }
    insec && fence { print }
  ' "$SKILL"
}

# How many fenced bash blocks that section holds. A restructure that added a
# second one would leave staging_block emitting both concatenated, which runs
# and grades something nobody wrote.
staging_fence_count() {
  awk '
    /^## Staging what belongs to the work$/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^```bash$/ { n++ }
    END { print n + 0 }
  ' "$SKILL"
}

# The exclusion suffixes, parsed out of the block rather than retyped. The set
# already exists in the block and in the prose beside it; a third copy here
# would let a seventh suffix ship with no case behind it.
block_suffixes() {
  grep -o "':(top,exclude,icase)[^']*'" "$BLOCK" | sed "s/^':(top,exclude,icase)//; s/'\$//"
}

# The block's `git add` invocations, with backslash continuations joined so the
# second add reads as one line.
add_invocations() {
  sed -e :a -e '/\\$/N; s/\\\n//; ta' "$BLOCK" | grep -F 'git add'
}

setup() {
  BLOCK="$BATS_TEST_TMPDIR/staging-block.sh"
  staging_block > "$BLOCK"
  [ -s "$BLOCK" ] || fail "no staging block extracted from $SKILL"
}

# ─── temp-repo scaffolding ─────────────────────────────────────────────────

# A fresh repo with one tracked file and one commit, cd'd into. Never inside
# the dotfiles working tree: AGENTS.md forbids a test writing there, and
# helpers/setup's scrub_git_env keeps an inherited GIT_DIR from redirecting
# these commits into the outer repo.
new_repo() {
  local tmp
  tmp="$(mktemp -d)"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet .
  printf 'seed\n' > tracked.txt
  git add tracked.txt
  git commit --quiet -m seed
}

# A repo mid-merge with a both-added conflict on both.txt. `AA` is one of the
# two unmerged porcelain codes carrying no `U` in either column, which is why
# the block reads `git ls-files -u` rather than porcelain.
new_conflicted_repo() {
  new_repo
  git checkout --quiet -b other
  printf 'other\n' > both.txt
  git add both.txt
  git commit --quiet -m other
  git checkout --quiet main
  printf 'mine\n' > both.txt
  git add both.txt
  git commit --quiet -m mine
  git merge other >/dev/null 2>&1 || true
}

run_block() {
  run bash "$BLOCK"
  [ "$status" -eq 0 ] || fail "the block itself exited $status: $output"
}

# val <key>: the value of a `key=value` line the block printed.
val() {
  printf '%s\n' "$output" | sed -n "s/^$1=//p"
}

# Everything after the residue marker - <RESIDUE> as the skill hands it to the
# report.
residue_lines() {
  printf '%s\n' "$output" | sed -n '/^residue<<</,$p' | tail -n +2
}

staged_paths() { git diff --cached --name-only | sort; }
untracked_paths() { git ls-files -o --exclude-standard | sort; }

# ─── the block is still where the tests look for it ────────────────────────

@test "the staging block is extracted from the skill exactly once" {
  [ "$(staging_fence_count)" -eq 1 ]
  printf '%s\n' "$(staging_block)" | grep -qF 'git add -u'
}

# ─── what gets left behind ─────────────────────────────────────────────────

@test "one untracked file per exclusion suffix is left unstaged" {
  local suffixes name
  suffixes="$(block_suffixes)"
  [ "$(printf '%s\n' "$suffixes" | wc -l | tr -d ' ')" -eq 6 ] \
    || fail "expected six exclusion suffixes, got: $suffixes"

  new_repo
  printf 'work\n' >> tracked.txt
  while IFS= read -r pat; do
    name="$(printf '%s' "$pat" | sed 's/\*/leftover/')"
    printf 'x\n' > "$name"
  done <<< "$suffixes"

  run_block
  [ "$(val staged)" = "yes" ]
  [ "$(staged_paths)" = "tracked.txt" ]
  [ "$(val residue_total)" -eq 6 ]
}

@test "an uppercase .ORIG is left unstaged" {
  new_repo
  printf 'x\n' > UPPER.ORIG
  printf 'x\n' > Mixed.Orig
  run_block
  [ "$(val staged)" = "no" ]
  [ "$(residue_lines)" = "$(printf 'Mixed.Orig\nUPPER.ORIG')" ]
}

@test "a hidden vim swap file is left unstaged" {
  new_repo
  printf 'x\n' > .foo.txt.swp
  run_block
  [ "$(val staged)" = "no" ]
  [ "$(residue_lines)" = ".foo.txt.swp" ]
}

# ─── what gets staged ──────────────────────────────────────────────────────

@test "an untracked ordinary file is staged" {
  new_repo
  printf 'x\n' > new.txt
  run_block
  [ "$(val staged)" = "yes" ]
  [ "$(staged_paths)" = "new.txt" ]
  [ "$(val residue_total)" -eq 0 ]
}

@test "a tracked file named *.orig has its modification staged" {
  new_repo
  printf 'v1\n' > keep.orig
  git add -f keep.orig
  git commit --quiet -m 'track an orig'
  printf 'v2\n' > keep.orig

  run_block
  [ "$(staged_paths)" = "keep.orig" ]
  [ "$(git show :keep.orig)" = "v2" ]
  [ "$(val residue_total)" -eq 0 ]
}

@test "residue staged by hand before the block runs stays staged and is not reported" {
  new_repo
  printf 'x\n' > hand.bak
  git add -f hand.bak
  printf 'x\n' > loose.bak

  run_block
  [ "$(staged_paths)" = "hand.bak" ]
  [ "$(residue_lines)" = "loose.bak" ]
}

@test "an untracked path holding a space is staged whole, and reported unquoted as residue" {
  new_repo
  printf 'x\n' > 'my file.txt'
  printf 'x\n' > 'my file.orig'

  run_block
  [ "$(staged_paths)" = "my file.txt" ]
  [ "$(residue_lines)" = "my file.orig" ]
}

@test "an untracked directory's ordinary file and leftover are handled separately" {
  new_repo
  mkdir d
  printf 'x\n' > d/ok.txt
  printf 'x\n' > d/left.orig

  run_block
  [ "$(staged_paths)" = "d/ok.txt" ]
  [ "$(residue_lines)" = "d/left.orig" ]
}

@test "a tree whose untracked files are all residue stages nothing" {
  new_repo
  printf 'x\n' > a.orig
  printf 'x\n' > b.rej

  run_block
  [ "$(val staged)" = "no" ]
  [ -z "$(staged_paths)" ]
  [ "$(val residue_total)" -eq 2 ]
}

# ─── the stops ─────────────────────────────────────────────────────────────

@test "a both-added conflict blocks on MERGE_HEAD with the index untouched" {
  new_conflicted_repo
  # Grade on the unmerged stage entries, not on an empty `git diff --cached`:
  # an unmerged index legitimately reports its paths as staged, so the obvious
  # assertion is red against a correct block.
  [ -n "$(git ls-files -u)" ]

  run_block
  [ "$(val blocked)" = "MERGE_HEAD" ]
  [ -z "$(val staged)" ]
  [ -n "$(git ls-files -u)" ]
}

@test "a merge whose conflict was resolved but not committed still blocks" {
  new_conflicted_repo
  printf 'resolved\n' > both.txt
  git add both.txt
  printf 'x\n' > new.txt
  # This is the case an index read alone cannot see: nothing is unmerged any
  # more, and porcelain shows ordinary work. Staging over it would produce a
  # two-parent merge commit carrying a message about new.txt.
  [ -z "$(git ls-files -u)" ]

  run_block
  [ "$(val blocked)" = "MERGE_HEAD" ]
  [ "$(untracked_paths)" = "new.txt" ]
}

@test "a conflicted stash apply blocks on the unmerged index alone" {
  new_repo
  printf 'a\n' > tracked.txt
  git stash push --quiet
  printf 'b\n' > tracked.txt
  git commit --quiet -am b
  git stash apply >/dev/null 2>&1 || true
  # The reverse case: unmerged stage entries with no operation file behind
  # them, which the path probe alone cannot see.
  [ -n "$(git ls-files -u)" ]
  [ ! -e "$(git rev-parse --git-dir)/MERGE_HEAD" ]

  run_block
  [ "$(val blocked)" = "unmerged-index" ]
}

@test "an embedded repository with no commit fails the add and reports no residue" {
  new_repo
  printf 'edit\n' >> tracked.txt
  mkdir emb
  ( cd emb && git init --quiet . )

  run_block
  [ "$(val add_tracked_exit)" -eq 0 ]
  [ "$(val add_rest_exit)" -ne 0 ]
  # git add -u already wrote its index update, so the tracked change survives
  # over a half-staged index - which is why this stops the ship.
  [ "$(staged_paths)" = "tracked.txt" ]
  printf '%s\n' "$output" | grep -qF 'residue<<<' && fail "residue was read after a failed add"
  [ -z "$(val residue_total)" ]
}

@test "an embedded repository with a commit is reported as a gitlink" {
  new_repo
  mkdir 'emb dir'
  ( cd 'emb dir' && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )

  run_block
  [ "$(val add_rest_exit)" -eq 0 ]
  [ "$(val staged)" = "yes" ]
  # The name carries a space, which is what pins substr() over a $4 field
  # split - the split truncates the path and the report names a directory
  # nobody has.
  [ "$(val gitlink)" = "emb dir" ]
}

# ─── the output's size, and where it is read from ──────────────────────────

@test "more than ten leftovers report their total and exactly ten paths" {
  new_repo
  local i=1
  while [ "$i" -le 12 ]; do
    printf 'x\n' > "r$i.bak"
    i=$((i + 1))
  done

  run_block
  [ "$(val residue_total)" -eq 12 ]
  [ "$(residue_lines | wc -l | tr -d ' ')" -eq 10 ]
}

@test "run from a subdirectory the block still stages and reads the whole tree" {
  new_repo
  printf 'x\n' > root.orig
  printf 'x\n' > rootwork.txt
  mkdir -p sub/deep
  printf 'x\n' > sub/deep/b.orig
  printf 'x\n' > sub/work.txt

  cd sub || fail "cd sub failed"
  run_block
  cd .. || fail "cd .. failed"

  # A mis-rooted exclusion fails silently in the dangerous direction: the
  # exclusions bind to sub/ while `:/` still pulls in the whole repo, so every
  # leftover is staged and the residue read comes back empty.
  [ "$(staged_paths)" = "$(printf 'rootwork.txt\nsub/work.txt')" ]
  [ "$(residue_lines)" = "$(printf 'root.orig\nsub/deep/b.orig')" ]
}

# ─── the block's shape ─────────────────────────────────────────────────────

@test "the block runs exactly two git adds and feeds neither a command substitution" {
  local adds
  adds="$(add_invocations)"
  [ "$(printf '%s\n' "$adds" | wc -l | tr -d ' ')" -eq 2 ] \
    || fail "expected two git add invocations, got: $adds"
  # This is the only case standing behind "no untracked path crosses out of
  # git and back in as a token in a command the agent assembles" - every other
  # case here would still pass with a classify-then-paste step reintroduced.
  case "$adds" in
    *'$('*) fail "a git add invocation carries a command substitution: $adds" ;;
    *'`'*) fail "a git add invocation carries a backtick substitution: $adds" ;;
  esac
}
