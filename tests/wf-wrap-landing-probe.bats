#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-wrap/SKILL.md"

# Step 1c's probe is read out of SKILL.md rather than copied here, for the same
# reason wf-wrap-gh-jq.bats extracts the Step 1 jq program: the skill is the
# only place it exists, so a copy would grade a stale expression and pass while
# the real one rotted.
#
# What the cases below grade is the one thing the probe is for - whether a
# branch whose work is already on the default branch is recognised as such. The
# answer differs per merge method, and which methods a repo allows is a repo
# setting the skill cannot read, so all three have to come out `landed=` and
# the unmerged branch has to come out silent.

# The one fenced bash block under "### Step 1c", with the skill's two
# placeholders bound to this fixture's refs.
probe_block() {
  awk '
    /^### Step 1c/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^```bash$/ { fence = 1; next }
    insec && fence && /^```$/ { fence = 0; next }
    insec && fence { print }
  ' "$SKILL" | sed -e 's|origin/<DEFAULT>|origin/main|g' -e 's|<FEATURE>|feature|g'
}

probe_fence_count() {
  awk '
    /^### Step 1c/ { insec = 1; next }
    insec && /^## / { insec = 0 }
    insec && /^```bash$/ { n++ }
    END { print n + 0 }
  ' "$SKILL"
}

setup() {
  PROBE="$BATS_TEST_TMPDIR/probe.sh"
  probe_block > "$PROBE"
  [ -s "$PROBE" ] || fail "no Step 1c block extracted from $SKILL"
}

# A repo with `main` at one commit and a two-commit `feature` branched off it,
# cd'd into. Two commits, not one: a single-commit branch is the case where
# every probe happens to agree, so it would grade nothing. Under
# $BATS_TEST_TMPDIR so bats clears it, and never inside the dotfiles working
# tree - AGENTS.md forbids a test writing there.
new_repo() {
  local tmp
  tmp="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXXXX")"
  cd "$tmp" || fail "cd $tmp failed"
  git init --quiet -b main .
  printf 'base\n' > base.txt
  git add base.txt
  git commit --quiet -m base
  git checkout --quiet -b feature
  printf 'one\n' > a.txt
  git add a.txt
  git commit --quiet -m one
  printf 'two\n' > b.txt
  git add b.txt
  git commit --quiet -m two
  git checkout --quiet main
}

# The skill reads origin/<DEFAULT>, so the fixture needs the branch to exist
# under that name. A local alias is enough - the probe only ever reads it.
publish_main() {
  git update-ref refs/remotes/origin/main "$(git rev-parse main)"
}

run_probe() {
  publish_main
  git checkout --quiet feature
  run bash "$PROBE"
  [ "$status" -eq 0 ] || fail "the probe itself exited $status: $output"
  # Every case reads `landed=` lines, and their absence is the stop. Without
  # this, a block that died after `head=` would look exactly like a branch
  # whose work never landed.
  printf '%s\n' "$output" | grep -qF 'probed=yes' \
    || fail "the block did not run to completion: $output"
}

landed() { printf '%s\n' "$output" | sed -n 's/^landed=//p' | sort | tr '\n' ' '; }

# ─── the block is still where the tests look for it ────────────────────────

@test "the Step 1c block is extracted from the skill exactly once" {
  [ "$(probe_fence_count)" -eq 1 ]
  printf '%s\n' "$(probe_block)" | grep -qF 'git cherry origin/main'
  printf '%s\n' "$(probe_block)" | grep -qF 'git merge-base --is-ancestor feature origin/main'
}

# ─── one row per merge method ──────────────────────────────────────────────

@test "a squash merge is recognised" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'

  run_probe
  [ "$(landed)" = "squash " ] || fail "expected only landed=squash, got: $(landed)"
}

@test "a rebase merge is recognised" {
  new_repo
  # GitHub replays the branch's commits onto the base as new commits and leaves
  # the local branch alone. A differing committer date is what makes the
  # replayed shas actually differ, which is the whole point of the case.
  GIT_COMMITTER_DATE='2030-01-01T00:00:00Z' git cherry-pick --quiet feature~1 feature
  [ "$(git rev-parse main)" != "$(git rev-parse feature)" ]

  run_probe
  [ "$(landed)" = "replayed " ] || fail "expected only landed=replayed, got: $(landed)"
}

@test "a merge commit is recognised" {
  new_repo
  git merge --no-ff feature -m 'merge (#1)' > /dev/null

  run_probe
  # The merge base becomes the branch tip here, so the squashed patch is empty
  # and matches nothing - ancestry is the only probe with an answer.
  [ "$(landed)" = "ancestor replayed " ] || fail "expected ancestry, got: $(landed)"
}

# ─── and the stop the probe exists for ─────────────────────────────────────

@test "a branch that never merged reports nothing landed" {
  new_repo
  printf 'unrelated\n' > u.txt
  git add u.txt
  git commit --quiet -m unrelated

  run_probe
  [ -z "$(landed | tr -d ' ')" ] || fail "an unmerged branch was called landed: $(landed)"
}

@test "a commit made after the merge still reports nothing landed" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'
  git checkout --quiet feature
  printf 'three\n' > c.txt
  git add c.txt
  git commit --quiet -m three

  # This is the case the guard exists for: the PR merged, and the branch has
  # moved since. Every probe has to stay silent or Step 4 discards the commit.
  run_probe
  [ -z "$(landed | tr -d ' ')" ] || fail "an unpushed commit was called landed: $(landed)"
}

@test "the head line names the local branch tip" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'

  run_probe
  # Step 1c compares this against <HEAD_OID> to tell "did not land" apart from
  # "a different tip landed", so it has to be the local branch and not the
  # probe commit the block builds.
  [ "$(printf '%s\n' "$output" | sed -n 's/^head=//p')" = "$(git rev-parse feature)" ]
}
