#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"
SCRIPT="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/stage-work.sh"
CALL='bash ~/.agents/skills/wf-ship/scripts/stage-work.sh'

# The cases run scripts/stage-work.sh itself, so no copy of its code can go
# stale. The call-site case checks that wf-ship still calls the script.
#
# The staging cases check what the index and the working tree hold after the
# script runs, not only what the script printed. A test that read only stdout
# would pass for a correctly worded skill that stages the wrong files.
#
# Output is read through key_values and section from helpers/setup, by
# position, as wf-ship reads it.

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

# skill_layout <skill>...: copies each named skill's scripts/ to
# $BATS_TEST_TMPDIR/skills/<skill>/scripts, the sibling layout ~/.agents/skills/
# holds, and prints the layout's root.
skill_layout() {
  local root="$BATS_TEST_TMPDIR/skills" s
  for s in "$@"; do
    mkdir -p "$root/$s"
    cp -R "$DOTFILES_ROOT/agents/skills/$s/scripts" "$root/$s/"
  done
  printf '%s\n' "$root"
}

run_script() {
  run bash "$SCRIPT"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
}

reset_index() { git reset --quiet; }

staged_paths() { git diff --cached --name-only | sort; }
untracked_paths() { git ls-files -o --exclude-standard | sort; }

# ─── the skill still calls the script ──────────────────────────────────────

@test "wf-ship calls the staging script once, alone in its block" {
  assert_sole_call "$SKILL" "$CALL"
}

# Step 0's porcelain is what a clean tree is read from. Under
# status.showUntrackedFiles=no, a tree holding only new files reads as clean.
@test "Step 0's porcelain read pins --untracked-files=normal" {
  local block
  block="$(awk '
    /^```bash$/ { if (done) exit; inblock = 1; next }
    inblock && /^```$/ { done = 1; inblock = 0; next }
    inblock' "$SKILL")"
  printf '%s\n' "$block" | grep -Fx 'git status --porcelain --untracked-files=normal' > /dev/null \
    || fail "wf-ship's Step 0 block does not run git status --porcelain --untracked-files=normal"
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
  [ "$(key_values staged)" = "yes" ]
  [ "$(staged_paths)" = "tracked.txt" ]
  [ "$(key_values residue_total)" -eq 6 ]
}

@test "an uppercase .ORIG is left unstaged" {
  new_repo
  printf 'x\n' > UPPER.ORIG
  printf 'x\n' > Mixed.Orig
  run_script
  [ "$(key_values staged)" = "no" ]
  [ "$(section residue)" = "$(printf 'Mixed.Orig\nUPPER.ORIG')" ]
}

@test "a hidden vim swap file is left unstaged" {
  new_repo
  printf 'x\n' > .foo.txt.swp
  run_script
  [ "$(key_values staged)" = "no" ]
  [ "$(section residue)" = ".foo.txt.swp" ]
}

# ─── what gets staged ──────────────────────────────────────────────────────

@test "an untracked ordinary file is staged, and arrives as a full patch in the gather" {
  new_repo
  printf 'x\n' > new.txt
  run_script
  [ "$(key_values staged)" = "yes" ]
  [ "$(key_values staged_total)" -eq 1 ]
  [ "$(staged_paths)" = "new.txt" ]
  [ "$(key_values residue_total)" -eq 0 ]
  [ "$(key_values residue_shown)" -eq 0 ]
  [ "$(key_values gather_exit)" -eq 0 ]
  [ "$(section_names)" = "$(printf 'residue\ngather')" ]
  section gather | grep -Fx 'A  new.txt' > /dev/null || fail "new.txt is not staged in the gather: $output"
  section gather | grep -Fx '+x' > /dev/null || fail "new.txt's content is not in the gather: $output"
}

# staged_total is the only place an untracked directory's size reaches the
# agent: porcelain collapses a directory to one line however many files are
# under it, and porcelain_total counts it that way.
@test "staged_total counts every path inside a collapsed untracked directory, and no gather runs" {
  new_repo
  mkdir -p vendored/deep
  local i=1
  while [ "$i" -le 12 ]; do
    printf 'x\n' > "vendored/deep/f$i.js"
    i=$((i + 1))
  done
  [ "$(git status --porcelain)" = "?? vendored/" ]

  run_script
  [ "$(key_values porcelain_total)" -eq 1 ]
  [ "$(key_values staged)" = "yes" ]
  [ "$(key_values staged_total)" -eq 12 ]
  [ -z "$(key_values gather_exit)" ]
  [ "$(section_names)" = "residue" ]
}

@test "porcelain_total counts the tree before the adds, whatever status.showUntrackedFiles says" {
  new_repo
  printf 'work\n' >> tracked.txt
  mkdir newdir
  printf 'x\n' > newdir/a
  printf 'x\n' > newdir/b
  printf 'x\n' > new.txt
  # The controls: bare porcelain prints four lines under `all`, where the
  # staged_total stop can never fire, and one under `no`, where it fires on
  # any new file.
  [ "$(git -c status.showUntrackedFiles=all status --porcelain | wc -l | tr -d ' ')" -eq 4 ]
  [ "$(git -c status.showUntrackedFiles=no status --porcelain | wc -l | tr -d ' ')" -eq 1 ]

  local v
  for v in normal all no; do
    git config status.showUntrackedFiles "$v"
    run_script
    [ "$(key_values porcelain_total)" -eq 3 ] \
      || fail "under status.showUntrackedFiles=$v, porcelain_total is $(key_values porcelain_total)"
    reset_index
  done
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
  [ "$(key_values residue_total)" -eq 0 ]
}

@test "residue staged by hand before the script runs stays staged and is not reported" {
  new_repo
  printf 'x\n' > hand.bak
  git add -f hand.bak
  printf 'x\n' > loose.bak

  run_script
  [ "$(staged_paths)" = "hand.bak" ]
  [ "$(section residue)" = "loose.bak" ]
}

@test "an untracked path holding a space is staged whole, and reported unquoted as residue" {
  new_repo
  printf 'x\n' > 'my file.txt'
  printf 'x\n' > 'my file.orig'

  run_script
  [ "$(staged_paths)" = "my file.txt" ]
  [ "$(section residue)" = "my file.orig" ]
}

@test "an untracked directory's ordinary file and leftover are handled separately" {
  new_repo
  mkdir d
  printf 'x\n' > d/ok.txt
  printf 'x\n' > d/left.orig

  run_script
  [ "$(staged_paths)" = "d/ok.txt" ]
  [ "$(section residue)" = "d/left.orig" ]
}

@test "a tree whose untracked files are all residue stages nothing and gathers nothing" {
  new_repo
  printf 'x\n' > a.orig
  printf 'x\n' > b.rej

  run_script
  [ "$(key_values staged)" = "no" ]
  [ "$(key_values staged_total)" -eq 0 ]
  [ -z "$(staged_paths)" ]
  [ "$(key_values residue_total)" -eq 2 ]
  [ "$(key_values residue_shown)" -eq 2 ]
  [ "$(section residue)" = "$(printf 'a.orig\nb.rej')" ]
  [ -z "$(key_values gather_exit)" ]
  [ "$(section_names)" = "residue" ]
}

# ─── the stops ─────────────────────────────────────────────────────────────

@test "a both-added conflict blocks on MERGE_HEAD with the index untouched" {
  new_conflicted_repo
  # Grade on the unmerged stage entries, not on an empty `git diff --cached`:
  # an unmerged index legitimately reports its paths as staged, so the obvious
  # assertion is red against a correct script.
  [ -n "$(git ls-files -u)" ]

  run_script
  [ "$(key_values blocked)" = "MERGE_HEAD" ]
  [ -z "$(key_values staged)" ]
  [ -z "$(section_names)" ]
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
  [ "$(key_values blocked)" = "MERGE_HEAD" ]
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
  [ "$(key_values blocked)" = "unmerged-index" ]
}

# The script runs under set -e. This case and the next also check that the
# script captures the status of each add: an add left to set -e stops the script
# before either exit line prints.
@test "an embedded repository with no commit fails the add, prints its error, and reports no residue" {
  new_repo
  printf 'edit\n' >> tracked.txt
  mkdir emb
  ( cd emb && git init --quiet . )

  run_script
  [ "$(key_values add_tracked_exit)" -eq 0 ]
  [ "$(key_values add_rest_exit)" -ne 0 ]
  # git add -u already wrote its index update, so the tracked change survives
  # over a half-staged index - which is why this stops the ship.
  [ "$(staged_paths)" = "tracked.txt" ]
  [ "$(section_names)" = "add_log" ]
  [ -z "$(key_values residue_total)" ]
  [ -z "$(key_values gather_exit)" ]
  section add_log | grep -F 'emb/' > /dev/null || fail "the add's error is not under add_log: $output"
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
  [ "$(key_values add_tracked_exit)" -ne 0 ]
  [ "$(key_values add_rest_exit)" -eq 0 ]
  [ "$(key_values staged)" = "yes" ]
  [ "$(section_names)" = "add_log" ]
  [ -z "$(key_values residue_total)" ]
  section add_log | grep -F 'keep.orig' > /dev/null || fail "the add's error is not under add_log: $output"
}

@test "an embedded repository with a commit is reported as a gitlink, and no gather runs" {
  new_repo
  mkdir 'emb dir'
  ( cd 'emb dir' && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )

  run_script
  [ "$(key_values add_rest_exit)" -eq 0 ]
  [ "$(key_values staged)" = "yes" ]
  # The name carries a space, which is what pins substr() over a $4 field
  # split - the split truncates the path and the report names a directory
  # nobody has.
  [ "$(key_values gitlink)" = "emb dir" ]
  [ -z "$(key_values gather_exit)" ]
  [ "$(section_names)" = "residue" ]
}

@test "a gitlink staged at the root is still reported from a subdirectory under diff.relative" {
  new_repo
  mkdir emb sub
  ( cd emb && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )
  printf 'x\n' > sub/work.txt
  git config diff.relative true
  cd sub || fail "cd sub failed"

  run_script
  # The control: this config narrows a bare raw read to sub/, gitlink dropped.
  [ "$(git diff --cached --raw | wc -l | tr -d ' ')" -eq 1 ]
  cd .. || fail "cd .. failed"
  [ "$(key_values gitlink)" = "emb" ]
  [ "$(key_values staged_total)" -eq 2 ]
  [ -z "$(key_values gather_exit)" ]
  [ "$(section_names)" = "residue" ]
}

@test "a newly staged gitlink is still reported under diff.ignoreSubmodules=all" {
  new_repo
  mkdir emb
  ( cd emb && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )
  printf 'x\n' > new.txt
  git config diff.ignoreSubmodules all

  run_script
  # The control: this config drops the gitlink from a bare raw read entirely,
  # rather than merely narrowing it the way diff.relative does above.
  [ "$(git diff --cached --raw --no-relative | wc -l | tr -d ' ')" -eq 1 ]
  [ "$(key_values gitlink)" = "emb" ]
  [ "$(key_values staged_total)" -eq 2 ]
  [ -z "$(key_values gather_exit)" ]
  [ "$(section_names)" = "residue" ]
}

# The mirror of the case above: an existing gitlink picking up a new commit in
# its embedded repo stages as a modification, not an add, so it never sets
# gitlink=. Left uncovered, the same config would still hide it from the
# porcelain read, and staged_total would run ahead of porcelain_total and trip
# the expanded-directory stop over a change that stop was never meant to catch.
@test "an existing gitlink's new commit is counted by both totals under diff.ignoreSubmodules=all" {
  new_repo
  mkdir emb
  ( cd emb && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e1 )
  git add emb >/dev/null 2>&1
  git commit --quiet -m 'add embedded repo as gitlink'
  ( cd emb && printf 'y\n' >> f && git add f && git commit --quiet -m e2 )
  git config diff.ignoreSubmodules all

  # The control: this config drops the bumped gitlink from a bare status read.
  [ -z "$(git status --porcelain --untracked-files=normal)" ]

  run_script
  [ -z "$(key_values gitlink)" ]
  [ "$(key_values porcelain_total)" -eq 1 ]
  [ "$(key_values staged_total)" -eq 1 ]
  [ "$(key_values gather_exit)" -eq 0 ]
  [ "$(section gather)" = "M  emb" ]
}

@test "any argument is a usage error that stages nothing" {
  new_repo
  printf 'x\n' > new.txt

  run bash "$SCRIPT" ready
  [ "$status" -eq 2 ]
  [ -z "$(key_values blocked)" ]
  [ -z "$(staged_paths)" ]
}

# ─── the gather ────────────────────────────────────────────────────────────

@test "a failing gather prints its status, and its error inside the gather section" {
  local root
  root="$(skill_layout wf-ship git-conventions)"
  printf '#!/usr/bin/env bash\necho "fatal: gather failed" >&2\nexit 3\n' \
    > "$root/git-conventions/scripts/gather.sh"
  new_repo
  printf 'x\n' > new.txt

  run bash "$root/wf-ship/scripts/stage-work.sh"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
  [ "$(key_values gather_exit)" -eq 3 ]
  [ "$(section gather)" = "fatal: gather failed" ]
  [ "$(staged_paths)" = "new.txt" ]
}

@test "a missing gather.sh stops the script before anything is staged" {
  local root
  root="$(skill_layout wf-ship)"
  new_repo
  printf 'x\n' > new.txt

  run --separate-stderr bash "$root/wf-ship/scripts/stage-work.sh"
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"dotfiles push"* ]] || fail "stderr does not name dotfiles push: $stderr"
  [ -z "$(staged_paths)" ]
}

@test "copies of wf-ship and git-conventions placed as sibling directories still gather" {
  local root
  root="$(skill_layout wf-ship git-conventions)"
  new_repo
  printf 'x\n' > new.txt

  run bash "$root/wf-ship/scripts/stage-work.sh"
  [ "$status" -eq 0 ] || fail "the script exited $status: $output"
  [ "$(key_values gather_exit)" -eq 0 ]
  section gather | grep -Fx 'A  new.txt' > /dev/null || fail "no gather from the copied layout: $output"
}

# ─── the output's size, and where it is read from ──────────────────────────

@test "more than ten leftovers report their total, exactly ten paths, and then the gather" {
  new_repo
  printf 'work\n' >> tracked.txt
  local i=1
  while [ "$i" -le 12 ]; do
    printf 'x\n' > "r$i.bak"
    i=$((i + 1))
  done

  run_script
  [ "$(key_values residue_total)" -eq 12 ]
  [ "$(key_values residue_shown)" -eq 10 ]
  [ "$(section residue | wc -l | tr -d ' ')" -eq 10 ]
  [ "$(section gather | sed -n 1p)" = "M  tracked.txt" ]
}

# A leftover survives the adds only by matching a suffix, so none can be named
# exactly like a marker; these come as close as the suffixes allow.
@test "leftovers named like a key and a marker are read as paths" {
  new_repo
  printf 'work\n' >> tracked.txt
  printf 'x\n' > 'staged=no.orig'
  printf 'x\n' > 'gather<<<~'

  run_script
  [ "$(key_values staged)" = "yes" ]
  [ "$(section residue)" = "$(printf 'gather<<<~\nstaged=no.orig')" ]
  [ "$(section gather | sed -n 1p)" = "M  tracked.txt" ]
}

@test "a git warning that prints a key-shaped path adds no key" {
  new_repo
  printf '* text eol=crlf\n' > .gitattributes
  git add .gitattributes 2>/dev/null
  git commit --quiet -m attrs
  local name k
  name="$(printf 'plain\ngather_exit=0')"
  printf 'x\n' > "$name"
  # The control: git add prints the path raw in its warning, so one line of
  # stderr reads gather_exit=0.
  git add -- "$name" 2>&1 | grep '^gather_exit=0' > /dev/null \
    || fail "git add no longer prints the forged line, so this case grades nothing"
  reset_index

  run_script
  for k in blocked porcelain_total add_tracked_exit add_rest_exit staged staged_total residue_total residue_shown gather_exit; do
    [ "$(key_values "$k" | wc -l | tr -d ' ')" -eq 1 ] \
      || fail "$(printf '%s has %s values in:\n%s' "$k" "$(key_values "$k" | wc -l | tr -d ' ')" "$output")"
  done
  [ "$(key_values gather_exit)" -eq 0 ]
}

@test "an embedded repository named like a key adds no key" {
  new_repo
  local name
  name="$(printf 'emb\nstaged=no')"
  mkdir "$name"
  ( cd "$name" && git init --quiet . && printf 'x\n' > f && git add f && git commit --quiet -m e )

  run_script
  [ "$(key_values staged)" = "yes" ]
  [ -n "$(key_values gitlink)" ]
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
  [ "$(section residue)" = "$(printf 'root.orig\nsub/deep/b.orig')" ]
}

# ─── the script's shape ────────────────────────────────────────────────────

@test "the script runs exactly two git adds and substitutes into neither's arguments" {
  local adds line
  adds="$(add_invocations)"
  [ "$(printf '%s\n' "$adds" | wc -l | tr -d ' ')" -eq 2 ] \
    || fail "expected two git add invocations, got: $adds"
  # This is the only case standing behind "no untracked path crosses out of
  # git and back in as a token in a command the agent assembles" - every other
  # case here would still pass with a classify-then-paste step reintroduced.
  # Each add's output is captured with $(...), so only the text after `git add`
  # is checked.
  while IFS= read -r line; do
    case "${line#*git add}" in
      *'$('*) fail "a git add invocation carries a command substitution: $line" ;;
      *'`'*) fail "a git add invocation carries a backtick substitution: $line" ;;
    esac
  done <<< "$adds"
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

  [ "$(key_values staged)" = "yes" ] || fail "unexpected output: $output"
  [ "$(key_values residue_total)" -eq 1 ] || fail "unexpected output: $output"
  [ "$(section residue)" = "left.orig" ] || fail "unexpected output: $output"
  [ "$(key_values gather_exit)" -eq 0 ] || fail "unexpected output: $output"
}
