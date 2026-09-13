#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"
SCRIPT="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/stage-work.sh"
CALL='bash ~/.agents/skills/wf-ship/scripts/stage-work.sh'

# The cases run scripts/stage-work.sh itself, so no copy of its code can go
# stale. The call-site case checks that wf-ship still calls the script.
#
# The cases test what the index and the working tree hold after the script
# runs, not what the script printed. A test that read only stdout would pass for
# a correctly worded skill that stages the wrong files.

# ─── reading the script ────────────────────────────────────────────────────

# The script without its comment lines, so a comment can name `git add` or a
# pathspec and the counts below stay correct.
script_code() { grep -v '^[[:space:]]*#' "$SCRIPT"; }

# The exclusion suffixes, read from the script, so the loop below makes one case
# for each suffix in the script. A separate assertion checks the count: a
# seventh suffix needs an edit here and in the script, and a real leftover that
# needs it.
# `.orig` and `.rej` are merge and patch leftovers, `~` and `.bak` editor
# backups, `.swp` and `.swo` vim swap files.
block_suffixes() {
  script_code | grep -o "':(top,exclude,icase)[^']*'" | sed "s/^':(top,exclude,icase)//; s/'\$//"
}

# The script's `git add` commands, with backslash continuations joined, so the
# second add reads as one line.
add_invocations() {
  script_code | join_continuations | grep -F 'git add'
}

# ─── temp-repo scaffolding ─────────────────────────────────────────────────

# A fresh repo with one tracked file and one commit, cd'd into. Under
# $BATS_TEST_TMPDIR so bats clears it with the test - a bare `mktemp -d` leaves
# one git repo per case behind on every run, forever. Never inside the dotfiles
# working tree: AGENTS.md forbids a test writing there, and helpers/setup's
# scrub_git_env keeps an inherited GIT_DIR from redirecting these commits into
# the outer repo.
new_repo() {
  local tmp
  tmp="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet .
  printf 'seed\n' > tracked.txt
  git add tracked.txt
  git commit --quiet -m seed
}

# A repo mid-merge with a both-added conflict on both.txt. `AA` is one of the
# two unmerged porcelain codes carrying no `U` in either column, which is why
# the script reads `git ls-files -u` rather than porcelain.
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

run_script() {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
}

reset_index() { git reset --quiet; }

# Everything after the residue marker - <RESIDUE> as the skill hands it to the
# report.
residue_lines() {
  printf '%s\n' "$output" | sed -n '/^residue<<</,$p' | tail -n +2
}

staged_paths() { git diff --cached --name-only | sort; }
untracked_paths() { git ls-files -o --exclude-standard | sort; }

# ─── the skill still calls the script ──────────────────────────────────────

@test "wf-ship calls the staging script once, alone in its block" {
  assert_sole_call "$SKILL" "$CALL"
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

  run_script
  [ "$(output_values staged)" = "yes" ]
  [ "$(staged_paths)" = "tracked.txt" ]
  [ "$(output_values residue_total)" -eq 6 ]
}

@test "an uppercase .ORIG is left unstaged" {
  new_repo
  printf 'x\n' > UPPER.ORIG
  printf 'x\n' > Mixed.Orig
  run_script
  [ "$(output_values staged)" = "no" ]
  [ "$(residue_lines)" = "$(printf 'Mixed.Orig\nUPPER.ORIG')" ]
}

@test "a hidden vim swap file is left unstaged" {
  new_repo
  printf 'x\n' > .foo.txt.swp
  run_script
  [ "$(output_values staged)" = "no" ]
  [ "$(residue_lines)" = ".foo.txt.swp" ]
}

# ─── what gets staged ──────────────────────────────────────────────────────

@test "an untracked ordinary file is staged" {
  new_repo
  printf 'x\n' > new.txt
  run_script
  [ "$(output_values staged)" = "yes" ]
  [ "$(output_values staged_total)" -eq 1 ]
  [ "$(staged_paths)" = "new.txt" ]
  [ "$(output_values residue_total)" -eq 0 ]
}

# staged_total is the only place an untracked directory's size reaches the
# agent: Step 0's `git status --porcelain` carries no -uall, so a directory
# arrives collapsed to one porcelain line however many files are under it.
@test "staged_total counts every path inside a collapsed untracked directory" {
  new_repo
  mkdir -p vendored/deep
  local i=1
  while [ "$i" -le 12 ]; do
    printf 'x\n' > "vendored/deep/f$i.js"
    i=$((i + 1))
  done
  # What the agent would have been handed for this tree, one line.
  [ "$(git status --porcelain)" = "?? vendored/" ]

  run_script
  [ "$(output_values staged)" = "yes" ]
  [ "$(output_values staged_total)" -eq 12 ]
}

@test "a tracked file named *.orig has its modification staged" {
  new_repo
  printf 'v1\n' > keep.orig
  git add -f keep.orig
  git commit --quiet -m 'track an orig'
  printf 'v2\n' > keep.orig

  run_script
  [ "$(staged_paths)" = "keep.orig" ]
  [ "$(git show :keep.orig)" = "v2" ]
  [ "$(output_values residue_total)" -eq 0 ]
}

@test "residue staged by hand before the script runs stays staged and is not reported" {
  new_repo
  printf 'x\n' > hand.bak
  git add -f hand.bak
  printf 'x\n' > loose.bak

  run_script
  [ "$(staged_paths)" = "hand.bak" ]
  [ "$(residue_lines)" = "loose.bak" ]
}

@test "an untracked path holding a space is staged whole, and reported unquoted as residue" {
  new_repo
  printf 'x\n' > 'my file.txt'
  printf 'x\n' > 'my file.orig'

  run_script
  [ "$(staged_paths)" = "my file.txt" ]
  [ "$(residue_lines)" = "my file.orig" ]
}

@test "an untracked directory's ordinary file and leftover are handled separately" {
  new_repo
  mkdir d
  printf 'x\n' > d/ok.txt
  printf 'x\n' > d/left.orig

  run_script
  [ "$(staged_paths)" = "d/ok.txt" ]
  [ "$(residue_lines)" = "d/left.orig" ]
}

@test "a tree whose untracked files are all residue stages nothing" {
  new_repo
  printf 'x\n' > a.orig
  printf 'x\n' > b.rej

  run_script
  [ "$(output_values staged)" = "no" ]
  [ "$(output_values staged_total)" -eq 0 ]
  [ -z "$(staged_paths)" ]
  [ "$(output_values residue_total)" -eq 2 ]
}

# ─── the stops ─────────────────────────────────────────────────────────────

@test "a both-added conflict blocks on MERGE_HEAD with the index untouched" {
  new_conflicted_repo
  # Grade on the unmerged stage entries, not on an empty `git diff --cached`:
  # an unmerged index legitimately reports its paths as staged, so the obvious
  # assertion is red against a correct script.
  [ -n "$(git ls-files -u)" ]

  run_script
  [ "$(output_values blocked)" = "MERGE_HEAD" ]
  [ -z "$(output_values staged)" ]
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

  run_script
  [ "$(output_values blocked)" = "MERGE_HEAD" ]
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

  run_script
  [ "$(output_values blocked)" = "unmerged-index" ]
}

# The script runs under set -e. This case and the next also check that the
# script captures the status of each add: an add left to set -e stops the script
# before either exit line prints.
@test "an embedded repository with no commit fails the add and reports no residue" {
  new_repo
  printf 'edit\n' >> tracked.txt
  mkdir emb
  ( cd emb && git init --quiet . )

  run_script
  [ "$(output_values add_tracked_exit)" -eq 0 ]
  [ "$(output_values add_rest_exit)" -ne 0 ]
  # git add -u already wrote its index update, so the tracked change survives
  # over a half-staged index - which is why this stops the ship.
  [ "$(staged_paths)" = "tracked.txt" ]
  ! printf '%s\n' "$output" | grep -qF 'residue<<<' || fail "residue was read after a failed add"
  [ -z "$(output_values residue_total)" ]
}

# The mirror of the case above, and the reason the residue read is gated on
# both adds rather than the second alone: the exclusions carry the unreadable
# path out of the second add's way, so `git add -u` can fail while `git add`
# succeeds. Reading residue there would have the report name leftovers for a
# run that stopped over a part-staged index.
@test "an unreadable tracked file fails only the first add and still reports no residue" {
  new_repo
  printf 'v1\n' > keep.orig
  git add -f keep.orig
  git commit --quiet -m 'track an orig'
  printf 'v2\n' > keep.orig
  printf 'x\n' > work.txt
  printf 'x\n' > loose.bak
  chmod 000 keep.orig
  # root reads a 000 file regardless, which would make the first add succeed
  # and grade nothing.
  if [ -r keep.orig ]; then
    chmod 644 keep.orig
    skip "this user can read a chmod 000 file"
  fi

  run_script
  chmod 644 keep.orig
  [ "$(output_values add_tracked_exit)" -ne 0 ]
  [ "$(output_values add_rest_exit)" -eq 0 ]
  [ "$(output_values staged)" = "yes" ]
  ! printf '%s\n' "$output" | grep -qF 'residue<<<' || fail "residue was read after a failed add"
  [ -z "$(output_values residue_total)" ]
}

@test "an embedded repository with a commit is reported as a gitlink" {
  new_repo
  mkdir 'emb dir'
  ( cd 'emb dir' && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )

  run_script
  [ "$(output_values add_rest_exit)" -eq 0 ]
  [ "$(output_values staged)" = "yes" ]
  # The name carries a space, which is what pins substr() over a $4 field
  # split - the split truncates the path and the report names a directory
  # nobody has.
  [ "$(output_values gitlink)" = "emb dir" ]
}

@test "any argument is a usage error that stages nothing" {
  new_repo
  printf 'x\n' > new.txt

  run bash "$SCRIPT" ready
  [ "$status" -eq 2 ]
  [ -z "$(output_values blocked)" ]
  [ -z "$(staged_paths)" ]
}

# ─── the output's size, and where it is read from ──────────────────────────

@test "more than ten leftovers report their total and exactly ten paths" {
  new_repo
  local i=1
  while [ "$i" -le 12 ]; do
    printf 'x\n' > "r$i.bak"
    i=$((i + 1))
  done

  run_script
  [ "$(output_values residue_total)" -eq 12 ]
  [ "$(residue_lines | wc -l | tr -d ' ')" -eq 10 ]
}

@test "run from a subdirectory the script still stages and reads the whole tree" {
  new_repo
  # tracked.txt is the only path here the bare `git add -u` is responsible for.
  # Every other one is untracked and reached by the second add's `:/`, so
  # without this the case grades the exclusions and never the first add - and a
  # directory-scoped `git add -u` would drop a tracked edit outside the cwd
  # from the commit with nothing turning red.
  printf 'work\n' >> tracked.txt
  printf 'x\n' > root.orig
  printf 'x\n' > rootwork.txt
  mkdir -p sub/deep
  printf 'x\n' > sub/deep/b.orig
  printf 'x\n' > sub/work.txt

  cd sub || fail "cd sub failed"
  run_script
  cd .. || fail "cd .. failed"

  # A mis-rooted exclusion fails silently in the dangerous direction: the
  # exclusions bind to sub/ while `:/` still pulls in the whole repo, so every
  # leftover is staged and the residue read comes back empty.
  [ "$(staged_paths)" = "$(printf 'rootwork.txt\nsub/work.txt\ntracked.txt')" ]
  [ "$(residue_lines)" = "$(printf 'root.orig\nsub/deep/b.orig')" ]
}

# ─── the script's shape ────────────────────────────────────────────────────

@test "the script runs exactly two git adds and feeds neither a command substitution" {
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

# ─── portability ───────────────────────────────────────────────────────────

# The other cases run the script under PATH's bash, as the skill's `bash <path>`
# call does. AGENTS.md also requires /bin/bash 3.2, which is /bin/bash on macOS.
@test "the script answers identically under /bin/bash and PATH's bash" {
  new_repo
  printf 'work\n' >> tracked.txt
  printf 'x\n' > new.txt
  printf 'x\n' > left.orig

  assert_script_portable reset_index "$SCRIPT"

  printf '%s\n' "$output" | grep -qF 'staged=yes' || fail "unexpected output: $output"
  printf '%s\n' "$output" | grep -qF 'residue_total=1' || fail "unexpected output: $output"
  printf '%s\n' "$output" | grep -qF 'left.orig' || fail "unexpected output: $output"
}
