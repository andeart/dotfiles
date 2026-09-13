#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-wrap/SKILL.md"
SCRIPT="$DOTFILES_ROOT/agents/skills/wf-wrap/scripts/landing-probe.sh"
CALL="bash ~/.agents/skills/wf-wrap/scripts/landing-probe.sh 'refs/remotes/origin/<DEFAULT>' 'refs/heads/<FEATURE>'"

# Step 1c's probe is scripts/landing-probe.sh, and the cases below run that
# file with this fixture's refs as its arguments, so a copy cannot grade a
# stale expression and pass while the real one rots. The call-site case pins
# that the skill still calls it, with the default branch first.
#
# What the cases below grade is the one thing the probe is for - whether a
# branch whose work is already on the default branch is recognised as such. The
# answer differs per merge method, and which methods a repo allows is a repo
# setting the skill cannot read, so all three have to come out `landed=`.
# Everything else has to come out silent, including the probe that could not
# run: `landed=` is what authorises Step 4 to discard the branch, so a probe
# that answers when it cannot see the default branch is worse than no probe.
#
# What the script's own comments do not carry:
#
# - The "cannot resolve" case below pins both failure guards. `NR &&`, because
#   `git cherry` writes errors to stderr and leaves the same empty stdout as a
#   branch whose every commit is upstream. The set -e guards, because an
#   unguarded merge-base stops the script before `head=`, and with it before
#   `probed=yes`.
# - `git cherry` skips merge commits, so the sweep speaks only for the
#   non-merge commits in `mb..<FEATURE>`. A branch that merged the default
#   branch into itself to resolve a conflict and then landed by replay would
#   report `landed=replayed` with the resolution still only on the branch.
#   Recorded as a bound rather than fixed - GitHub declines the rebase button
#   in that shape, so nothing here can reproduce it.

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
  run bash "$SCRIPT" refs/remotes/origin/main refs/heads/feature
  [ "$status" -eq 0 ] || fail "the probe itself exited $status: $output"
  # Every case reads `landed=` lines, and their absence is the stop. Without
  # this, a script that died after `head=` would look exactly like a branch
  # whose work never landed.
  printf '%s\n' "$output" | grep -qF 'probed=yes' \
    || fail "the probe did not run to completion: $output"
}

landed() { output_values landed | sort | tr '\n' ' '; }

# ─── the skill still calls the script ──────────────────────────────────────

@test "wf-wrap calls the landing probe once, alone in its block" {
  assert_sole_call "$SKILL" "$CALL"
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
  # The merge base becomes the branch tip here, so `mb..feature` is empty: the
  # squashed patch matches nothing and the sweep has no commit to speak for.
  # Ancestry is the only probe with an answer.
  [ "$(landed)" = "ancestor " ] || fail "expected ancestry alone, got: $(landed)"
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

@test "a probe that cannot resolve the default branch reports nothing landed" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'
  git checkout --quiet feature

  # No publish_main, so origin/main does not resolve and all three probes fail.
  # git cherry writes its errors to stderr, so the per-commit sweep sees the
  # same empty stdout it sees for a branch that fully landed - which is why it
  # requires a commit to have been read before it answers. Without that, a
  # broken probe prints the one line that authorises Step 4's discard.
  run bash "$SCRIPT" refs/remotes/origin/main refs/heads/feature
  printf '%s\n' "$output" | grep -qF 'probed=yes' \
    || fail "the probe did not run to completion: $output"
  [ -z "$(landed | tr -d ' ')" ] || fail "a failed probe was called landed: $(landed)"
}

@test "the head line names the local branch tip" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'

  run_probe
  # Step 1c compares this against <HEAD_OID> to tell "did not land" apart from
  # "a different tip landed", so it has to be the local branch and not the
  # probe commit the script builds.
  [ "$(output_values head)" = "$(git rev-parse refs/heads/feature)" ]
}

# A usage error is never the no-landed stop: it prints no `landed=` line, so it
# cannot authorise the discard, and wf-wrap stops on its exit status instead.
# The fixture is a squash merge, so a probe that ran anyway would answer.
@test "an argument that is not a full refname is a usage error with no landed line" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'
  publish_main
  git checkout --quiet feature

  local args
  for args in 'refs/remotes/origin/main --output=pwned.txt' '-evil refs/heads/feature' \
              'origin/main refs/heads/feature' 'refs/remotes/origin/main feature'; do
    # shellcheck disable=SC2086 # each entry is two words on purpose
    run bash "$SCRIPT" $args
    [ "$status" -eq 2 ] || fail "accepted a non-refname argument ($status): $args"
    [ -z "$(landed | tr -d ' ')" ] || fail "a usage error was called landed: $args"
  done
}

# git resolves a short name to a same-named tag before the branch, and a fetch
# brings in the remote's tags. The tag here sits on the default branch, so a
# probe reading it would call work that never merged `landed=ancestor`.
@test "a tag named like the branch does not stand in for it" {
  new_repo
  git tag feature main

  run_probe
  [ -z "$(landed | tr -d ' ')" ] || fail "a same-named tag was called landed: $output"
  [ "$(output_values head)" = "$(git rev-parse refs/heads/feature)" ] \
    || fail "head= did not name the branch tip: $output"
}

# ─── portability ───────────────────────────────────────────────────────────

@test "the probe answers identically under /bin/bash and PATH's bash" {
  new_repo
  git merge --squash feature > /dev/null
  git commit --quiet -m 'squash (#1)'
  publish_main
  git checkout --quiet feature

  assert_script_portable : "$SCRIPT" refs/remotes/origin/main refs/heads/feature

  [ "$(landed)" = "squash " ] || fail "expected only landed=squash, got: $(landed)"
  printf '%s\n' "$output" | grep -qF 'probed=yes' || fail "unexpected output: $output"
}
