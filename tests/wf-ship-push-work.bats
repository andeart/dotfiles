#!/usr/bin/env bats

load helpers/setup

bats_require_minimum_version 1.5.0

SKILL="$DOTFILES_ROOT/agents/skills/wf-ship/SKILL.md"
PUSH="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/push-work.sh"
LOOKUP="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/pr-lookup.sh"
COMMIT="$DOTFILES_ROOT/agents/skills/wf-ship/scripts/commit.sh"

# Every case pushes to a bare repository under the test's temp directory, never
# a real remote, and gh is a stub on PATH. setup_file builds the origin and its
# clone once and setup copies them per case, at about a quarter of the cost of
# building them.
#
# The cases check the remote and the refs, not only the output: a script that
# printed the right keys over the wrong push would pass on output alone. Output
# is read by position through key_values and section from helpers/setup.
#
# One case per mode, and one pr-lookup case, runs under both shells. The rest
# run under PATH's bash, because the suite runs at every commit and its wall
# clock is pinned by its longest file.

setup_file() {
  local world="$BATS_FILE_TMPDIR/world"
  mkdir -p "$world"
  git init --quiet --bare "$world/origin.git"
  git clone --quiet "$world/origin.git" "$world/clone" 2>/dev/null
  (
    cd "$world/clone" || exit 1
    printf 'app\n' > app.sh
    git add app.sh
    git commit --quiet -m seed
    git push --quiet -u origin main 2>/dev/null
  )
}

setup() {
  STUB_BIN="$BATS_TEST_TMPDIR/stubs"
  mkdir -p "$STUB_BIN"
  stub_gh
  PATH="$STUB_BIN:$PATH"
  fresh_world
}

# fresh_world: a copy of setup_file's world at $BATS_TEST_TMPDIR/world, cd'd
# into the clone. A world already there is moved aside, so a second copy in one
# case has the same paths as the first: git push prints the origin's path, and
# the portability cases compare two runs' output.
fresh_world() {
  local world="$BATS_TEST_TMPDIR/world"
  if [ -e "$world" ]; then
    mv "$world" "$(mktemp -d "$BATS_TEST_TMPDIR/old.XXXXXX")/"
  fi
  cp -R "$BATS_FILE_TMPDIR/world" "$world"
  ORIGIN="$world/origin.git"
  cd "$world/clone" || fail "cd $world/clone failed"
  # The copy still names setup_file's origin, which every case would share.
  git remote set-url origin "$ORIGIN"
}

# stub_gh: a gh that records each call in $STUB_BIN/calls. With
# $STUB_BIN/payload present it answers by running the --jq filter it was
# passed over that payload, so the cases exercise the script's own filter.
# Without one it fails as gh does for a branch with no pull request, with an
# ESC and a CR in the message.
stub_gh() {
  cat > "$STUB_BIN/gh" <<EOF
#!/bin/sh
printf '%s\n' "\$*" >> "$STUB_BIN/calls"
if [ ! -f "$STUB_BIN/payload" ]; then
  printf 'no pull requests found for branch \033[31mfeat\r\n' >&2
  exit 1
fi
jqf=
while [ \$# -gt 0 ]; do
  case "\$1" in
    --jq) jqf=\$2; shift 2 ;;
    *) shift ;;
  esac
done
exec jq -r "\$jqf" < "$STUB_BIN/payload"
EOF
  chmod +x "$STUB_BIN/gh"
}

# pr_payload <json>: the pull request the stub answers with.
pr_payload() { printf '%s' "$1" > "$STUB_BIN/payload"; }

# remote_ref <branch>: the origin's commit for <branch>, or nothing.
remote_ref() { git --git-dir="$ORIGIN" rev-parse --verify --quiet "refs/heads/$1" || true; }

# commit_file <path> <content>: <content> written to <path> and committed.
commit_file() {
  mkdir -p "$(dirname -- "$1")"
  printf '%s\n' "$2" > "$1"
  git add -- "$1"
  git commit --quiet -m "change $1"
}

# advance_origin <path> <content>: a commit on origin's main from a second
# clone, fetched into this one.
advance_origin() {
  local other
  other="$(mktemp -d "$BATS_TEST_TMPDIR/other.XXXXXX")"
  git clone --quiet "$ORIGIN" "$other/clone" 2>/dev/null
  ( cd "$other/clone" && commit_file "$1" "$2" && git push --quiet origin main 2>/dev/null ) \
    || fail "advancing origin's main failed"
  git fetch --quiet origin
}

# refs_snapshot: every local branch with its commit, then what HEAD is.
refs_snapshot() {
  git for-each-ref --format='%(refname) %(objectname)' refs/heads
  git symbolic-ref --quiet HEAD || git rev-parse HEAD
}

run_push() { run bash "$PUSH" "$@"; }

# ─── feature mode ──────────────────────────────────────────────────────────

@test "no upstream: the branch is pushed and its pull request looked up" {
  git checkout --quiet -b feat
  commit_file a.txt a

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "${lines[0]}" = "upstream=no" ]
  [ "$(key_values unpushed_total)" -eq 1 ]
  [ "$(key_values push_exit)" -eq 0 ]
  [ "$(key_values pushed_total)" -eq 1 ]
  [ "$(section pushed)" = "a.txt" ]
  [ "$(key_values pr)" = "none" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  [ "$(remote_ref feat)" = "$(git rev-parse HEAD)" ]
  [ "$(git rev-parse --abbrev-ref '@{upstream}')" = "origin/feat" ]
  grep -F 'pr view' "$STUB_BIN/calls" > /dev/null || fail "the lookup did not run"
}

@test "an upstream with unpushed commits: only their paths are listed" {
  git checkout --quiet -b feat
  commit_file a.txt a
  git push --quiet -u origin feat 2>/dev/null
  commit_file b.txt b

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values upstream)" = "yes" ]
  [ "$(key_values unpushed_total)" -eq 1 ]
  [ "$(section pushed)" = "b.txt" ]
  [ "$(remote_ref feat)" = "$(git rev-parse HEAD)" ]
}

@test "nothing to push: the remote is untouched and the pull request still looked up" {
  git checkout --quiet -b feat
  commit_file a.txt a
  git push --quiet -u origin feat 2>/dev/null
  local before
  before="$(remote_ref feat)"
  pr_payload '{"url":"https://github.com/o/r/pull/1","isDraft":true,"body":"Issue: [ZZZ-0](https://example.invalid/ZZZ-0/)\r\n\r\n## Summary"}'

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values pushed)" = "no" ]
  [ -z "$(key_values push_exit)" ]
  [ -z "$(key_values pushed_total)" ]
  [ "$(key_values pr_url)" = "https://github.com/o/r/pull/1" ]
  [ "$(key_values pr_draft)" = "yes" ]
  [ "$(section pr_first_line)" = "Issue: [ZZZ-0](https://example.invalid/ZZZ-0/)" ]
  [ "$(section_names)" = "pr_first_line" ]
  [ "$(remote_ref feat)" = "$before" ]
}

@test "a docs-only branch lists only its own paths after the default branch moves" {
  git checkout --quiet -b spec
  commit_file docs/spec.md spec
  advance_origin app.sh 'app v2'
  # The control: a two-dot range diffs the tips, so it lists origin's app.sh.
  [ "$(git diff --name-only origin/main..HEAD | wc -l | tr -d ' ')" -eq 2 ]

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(section pushed)" = "docs/spec.md" ]
  [ "$(key_values pushed_docs_only)" = "yes" ]
}

@test "a non-ASCII docs path is docs-only under both core.quotePath values" {
  local q
  for q in true false; do
    git checkout --quiet -b "spec-$q" main
    commit_file "docs/$(printf '\303\251').md" e
    git config core.quotePath "$q"
    run_push --default main
    [ "$status" -eq 0 ] || fail "core.quotePath=$q: exit $status: $output"
    [ "$(key_values pushed_docs_only)" = "yes" ] || fail "core.quotePath=$q: $output"
  done
  # The control: git quotes the path by default, so a bare docs/ prefix test
  # fails it.
  [ "$(git -c core.quotePath=true diff --name-only main...HEAD)" = '"docs/\303\251.md"' ]
}

@test "a path under a top-level directory named \"docs is not docs-only" {
  git checkout --quiet -b quoted
  commit_file '"docs/fake.md' x
  # The control: git quotes the whole path, leading quote escaped.
  [ "$(git diff --name-only main...HEAD)" = '"\"docs/fake.md"' ]

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values pushed_total)" -eq 1 ]
  [ "$(key_values pushed_docs_only)" = "no" ]
}

@test "a branch holding one empty commit pushes no paths and is not docs-only" {
  git checkout --quiet -b empty
  git commit --quiet --allow-empty -m empty

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values unpushed_total)" -eq 1 ]
  [ "$(key_values pushed_total)" -eq 0 ]
  [ "$(key_values pushed_shown)" -eq 0 ]
  [ "$(key_values pushed_docs_only)" = "no" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  [ -n "$(remote_ref empty)" ]
}

@test "a push past the path cap lists the first paths, and reads docs-only from every path" {
  git checkout --quiet -b big
  mkdir docs
  local i=1
  while [ "$i" -le 100 ]; do
    printf 'x\n' > "docs/d$i.md"
    i=$((i + 1))
  done
  # Sorts after docs/, so only the uncapped read sees it.
  printf 'x\n' > zz.txt
  git add docs zz.txt
  git commit --quiet -m big

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values pushed_total)" -eq 101 ]
  [ "$(key_values pushed_shown)" -eq 100 ]
  [ "$(section pushed | wc -l | tr -d ' ')" -eq 100 ]
  ! section pushed | grep -Fx zz.txt > /dev/null || fail "a path past the cap is listed: $output"
  [ "$(key_values pushed_docs_only)" = "no" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  [ "$(remote_ref big)" = "$(git rev-parse HEAD)" ]
}

@test "run from a subdirectory under diff.relative, the paths are the whole branch's" {
  git checkout --quiet -b spec
  commit_file docs/a.md a
  commit_file docs/b.md b
  git config diff.relative true
  cd docs || fail "cd docs failed"
  # The control: this config strips the directory from a bare listing.
  [ "$(git diff --name-only origin/main...HEAD | sed -n 1p)" = "a.md" ]

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(section pushed)" = "$(printf 'docs/a.md\ndocs/b.md')" ]
  [ "$(key_values pushed_docs_only)" = "yes" ]
}

@test "a rejected push skips the lookup and prints the rejection under git_log" {
  printf '#!/bin/sh\necho "no pushes today" >&2\nexit 1\n' > "$ORIGIN/hooks/pre-receive"
  chmod +x "$ORIGIN/hooks/pre-receive"
  git checkout --quiet -b feat
  commit_file a.txt a

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values push_exit)" -ne 0 ]
  [ -z "$(key_values pr)" ]
  [ -z "$(key_values pr_url)" ]
  [ ! -e "$STUB_BIN/calls" ] || fail "gh ran after a rejected push"
  [ -z "$(remote_ref feat)" ]
  section git_log | grep -F 'no pushes today' > /dev/null || fail "the rejection is not under git_log: $output"
}

@test "a pull request body opening with a marker stays in its own section" {
  git checkout --quiet -b feat
  commit_file a.txt a
  git push --quiet -u origin feat 2>/dev/null
  commit_file b.txt b
  pr_payload '{"url":"https://github.com/o/r/pull/2","isDraft":false,"body":"pushed<<<\ngit_log<<<"}'

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(section_names)" = "$(printf 'pushed\npr_first_line\ngit_log')" ]
  [ "$(section pushed)" = "b.txt" ]
  [ "$(section pr_first_line)" = "pushed<<<" ]
  [ "$(key_values pr_draft)" = "no" ]
}

@test "a pre-push hook's output stays under git_log" {
  printf '#!/bin/sh\necho pushed_total=99\necho "pushed<<<"\necho push_exit=7 >&2\n' > .git/hooks/pre-push
  chmod +x .git/hooks/pre-push
  git checkout --quiet -b feat
  commit_file a.txt a

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values pushed_total)" = "1" ]
  [ "$(key_values push_exit)" = "0" ]
  [ "$(section pushed)" = "a.txt" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  section git_log | grep -Fx 'pushed_total=99' > /dev/null || fail "the hook's output is missing: $output"
}

# ship_call <script>: the call wf-ship's "Committing" chains, written to
# $BATS_TEST_TMPDIR/ship.sh so its quoted heredoc delimiter needs no escaping
# inside a `bash -c` string. Run it as `bash ship.sh <commit.sh> <push-work.sh>`.
ship_call() {
  cat > "$BATS_TEST_TMPDIR/ship.sh" <<'SH'
bash "$1" <<'EOF' && bash "$2" --default main
Add a
EOF
SH
}

@test "a commit hook's output never reaches the chained push's keys" {
  # A hook that names each staged file, as a linter does, over a file whose
  # name reads as keys.
  printf '#!/bin/sh\ngit diff --cached --name-only -z | xargs -0 printf "checked %%s\\n"\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  git checkout --quiet -b feat
  local name
  name="$(printf 'n\npushed=no\npr=none')"
  printf 'a\n' > "$name"
  git add -- "$name"
  ship_call
  # The control: the hook prints the forged lines when the commit runs.
  [ "$(git diff --cached --name-only -z | xargs -0 printf 'checked %s\n' | grep -cx 'pushed=no')" -eq 1 ]

  run bash "$BATS_TEST_TMPDIR/ship.sh" "$COMMIT" "$PUSH"
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "${lines[0]}" = "upstream=no" ] || fail "output does not start with push-work's keys: $output"
  [ -z "$(key_values pushed)" ]
  [ "$(key_values pr)" = "none" ]
  [ "$(key_values pushed_total)" = "1" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  [ "$(git log -1 --format=%s)" = "Add a" ]
  [ "$(remote_ref feat)" = "$(git rev-parse HEAD)" ]
}

@test "a failed commit prints its hook output under commit_log, and the push never runs" {
  printf '#!/bin/sh\nprintf "pushed=no\\nlint \\033[31mfailed\\r\\n"\nexit 1\n' > .git/hooks/pre-commit
  chmod +x .git/hooks/pre-commit
  git checkout --quiet -b feat
  printf 'a\n' > a.txt
  git add a.txt
  local head
  head="$(git rev-parse HEAD)"
  ship_call

  run bash "$BATS_TEST_TMPDIR/ship.sh" "$COMMIT" "$PUSH"
  [ "$status" -eq 1 ]
  [ "${lines[0]}" = "commit_log<<<" ]
  [ "$(section commit_log)" = "$(printf 'pushed=no\nlint [31mfailed')" ] || fail "unexpected commit_log: $output"
  [ "$(git rev-parse HEAD)" = "$head" ]
  [ "$(git diff --cached --name-only)" = "a.txt" ]
  [ -z "$(remote_ref feat)" ]
}

@test "commit.sh refuses any argument, with nothing committed" {
  printf 'a\n' > a.txt
  git add a.txt
  local head
  head="$(git rev-parse HEAD)"
  run bash "$COMMIT" -m x <<< 'Add a'
  [ "$status" -eq 2 ]
  [ "$(git rev-parse HEAD)" = "$head" ]
}

@test "commit.sh commits identically under /bin/bash and PATH's bash" {
  local sh ran=
  while IFS= read -r sh; do
    printf '%s\n' "$sh" >> a.txt
    git add a.txt
    run "$sh" "$COMMIT" <<< "Add a from $sh"
    [ "$status" -eq 0 ] || fail "$sh exited $status: $output"
    [ -z "$output" ] || fail "$sh printed output on success: $output"
    [ "$(git log -1 --format=%s)" = "Add a from $sh" ] || fail "$sh did not commit the message"
    ran="$ran$sh"$'\n'
  done < <(shells_among "${SCRIPT_SHELLS[@]}")
  assert_shells_covered "$ran" "${SCRIPT_SHELLS[@]}"
}

@test "remote text under git_log loses its ESC and CR bytes" {
  printf '#!/bin/sh\nprintf "evil \\033[31mRED\\033[0m tail \\rOVER\\n"\n' > "$ORIGIN/hooks/pre-receive"
  chmod +x "$ORIGIN/hooks/pre-receive"
  git checkout --quiet -b feat
  commit_file a.txt a
  # The control: a plain push carries both bytes through.
  [ -n "$(git push origin HEAD:refs/heads/probe 2>&1 | LC_ALL=C tr -dc '\033\r')" ] \
    || fail "the hook's ESC and CR did not reach git push's output"

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values push_exit)" -eq 0 ]
  section git_log | grep -F 'evil [31mRED[0m tail' > /dev/null || fail "the remote text is missing: $output"
  [ -z "$(printf '%s' "$output" | LC_ALL=C tr -dc '\033\r')" ] || fail "an ESC or a CR reached the output"
}

@test "the default branch and a detached HEAD are refused, with nothing pushed" {
  commit_file a.txt a
  local before
  before="$(remote_ref main)"

  run_push --default main
  [ "$status" -eq 2 ]
  git tag main
  run_push --default main
  [ "$status" -eq 2 ] || fail "a tag named main let the default branch through: $output"
  git checkout --quiet --detach
  run_push --default main
  [ "$status" -eq 2 ]
  [ "$(remote_ref main)" = "$before" ]
  [ ! -e "$STUB_BIN/calls" ]
}

@test "a missing pr-lookup.sh stops before anything is pushed" {
  local lonely="$BATS_TEST_TMPDIR/lonely"
  mkdir -p "$lonely"
  cp "$PUSH" "$lonely/"
  git checkout --quiet -b feat
  commit_file a.txt a

  run --separate-stderr bash "$lonely/push-work.sh" --default main
  [ "$status" -ne 0 ]
  [ -z "$output" ]
  [[ "$stderr" == *"dotfiles push"* ]] || fail "stderr does not name dotfiles push: $stderr"
  [ -z "$(remote_ref feat)" ]
}

@test "nothing to push and no pull request: gh's filtered error comes through under gh_log" {
  git checkout --quiet -b feat
  commit_file a.txt a
  git push --quiet -u origin feat 2>/dev/null

  run_push --default main
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values pushed)" = "no" ]
  [ "$(key_values pr)" = "none" ]
  [ "$(section_names)" = "gh_log" ]
  [ "$(section gh_log)" = "no pull requests found for branch [31mfeat" ]
}

@test "pr-lookup output off its contract reads as no pull request, never as an exit" {
  local lonely="$BATS_TEST_TMPDIR/lonely"
  mkdir -p "$lonely"
  cp "$PUSH" "$lonely/"
  printf '#!/usr/bin/env bash\nprintf "pr_url=x\\nstale \\033[31mformat\\n"\n' > "$lonely/pr-lookup.sh"
  git checkout --quiet -b feat
  commit_file a.txt a

  run bash "$lonely/push-work.sh" --default main
  [ "$status" -eq 0 ] || fail "exit $status after a landed push: $output"
  [ "$(key_values push_exit)" -eq 0 ]
  [ "$(key_values pr)" = "none" ]
  [ -z "$(key_values pr_url)" ]
  [ "$(section_names)" = "$(printf 'pushed\ngit_log')" ]
  [ "$(remote_ref feat)" = "$(git rev-parse HEAD)" ]

  run bash "$lonely/push-work.sh" --default main
  [ "$status" -eq 0 ] || fail "exit $status with nothing to push: $output"
  [ "$(key_values pushed)" = "no" ]
  [ "$(key_values pr)" = "none" ]
  [ "$(section_names)" = "gh_log" ]
  section gh_log | grep -Fx 'stale [31mformat' > /dev/null || fail "the off-contract output is not under gh_log: $output"
}

@test "the scripts that filter remote text define strip_controls identically" {
  local defs
  defs="$(grep -h '^strip_controls()' "$PUSH" "$LOOKUP" "$COMMIT")"
  [ "$(printf '%s\n' "$defs" | wc -l | tr -d ' ')" -eq 3 ] || fail "expected one definition per script: $defs"
  [ "$(printf '%s\n' "$defs" | sort -u | wc -l | tr -d ' ')" -eq 1 ] || fail "the definitions differ: $defs"
}

@test "wf-ship commits through commit.sh with the flow's next command chained" {
  assert_one_line "$SKILL" "bash ~/.agents/skills/wf-ship/scripts/commit.sh <<'EOF' && <the flow's next command>"
}

# ─── move mode ─────────────────────────────────────────────────────────────

@test "a checkout that would overwrite an untracked file creates no branch" {
  commit_file f.txt v1
  git push --quiet origin main 2>/dev/null
  git mv f.txt g.txt
  git commit --quiet -m move
  printf 'local\n' > f.txt
  local before
  before="$(refs_snapshot)"

  run --separate-stderr bash "$PUSH" --default main --move-to cut
  [ "$status" -eq 1 ] || fail "exit $status: $output"
  [[ "$stderr" == *"f.txt"* ]] || fail "stderr does not name the untracked file: $stderr"
  [ "$(refs_snapshot)" = "$before" ]
  [ -z "$(remote_ref cut)" ]
}

@test "move mode cuts the branch at the upstream and pushes the cherry-picked commits, beside a same-named tag" {
  commit_file m.txt m
  local up
  up="$(git rev-parse origin/main)"
  git tag ship-it

  run_push --default main --move-to ship-it
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values cherry_pick_exit)" -eq 0 ]
  [ "$(key_values push_exit)" -eq 0 ]
  [ "$(section pushed)" = "m.txt" ]
  [ -z "$(key_values pr)" ]
  [ "$(git symbolic-ref HEAD)" = "refs/heads/ship-it" ]
  [ "$(git rev-parse HEAD^)" = "$up" ]
  [ "$(remote_ref ship-it)" = "$(git rev-parse HEAD)" ]
  [ ! -e "$STUB_BIN/calls" ]
}

@test "a conflicting cherry-pick pushes nothing, prints no pushed_total, and shows the conflict under git_log" {
  local evil
  evil="$(printf 'evil\npushed_total=99')"
  commit_file "$evil" base
  git push --quiet origin main 2>/dev/null
  printf 'mine\n' > "$evil"
  git commit --quiet -am mine
  advance_origin "$evil" theirs

  run_push --default main --move-to conflicted
  [ "$status" -eq 0 ] || fail "exit $status: $output"
  [ "$(key_values cherry_pick_exit)" -ne 0 ]
  [ -z "$(key_values pushed_total)" ]
  [ "$(section_names)" = "git_log" ]
  section git_log | grep -F 'CONFLICT' > /dev/null || fail "the conflict is not under git_log: $output"
  [ -z "$(remote_ref conflicted)" ]
}

@test "a refused name, an existing branch, another --default and a missing upstream create nothing" {
  commit_file m.txt m
  git branch taken
  local before name
  before="$(refs_snapshot)"

  for name in -leading-dash 'has space' dot.name "$(printf 'caf\303\251')" taken ''; do
    run_push --default main --move-to "$name"
    [ "$status" -eq 2 ] || fail "--move-to '$name' exited $status: $output"
  done
  run_push --default trunk --move-to fine
  [ "$status" -eq 2 ]
  git branch --unset-upstream main
  run_push --default main --move-to fine
  [ "$status" -eq 2 ] || fail "a default branch with no upstream exited $status: $output"
  [ "$(refs_snapshot)" = "$before" ]
  [ -z "$(remote_ref fine)" ]
}

@test "malformed argument lists are refused with nothing created" {
  git checkout --quiet -b feat
  commit_file a.txt a
  local before list
  before="$(refs_snapshot)"

  for list in '' '--default' '--default main --move-to' '--default main --default main' \
              '--default main --move-to a --move-to b' '--move-to a --default main' \
              '--bogus main' '--default main extra'; do
    # Unquoted on purpose: each list is several arguments.
    run bash "$PUSH" $list
    [ "$status" -eq 2 ] || fail "'$list' exited $status: $output"
  done
  [ "$(refs_snapshot)" = "$before" ]
  [ -z "$(remote_ref feat)" ]
}

# ─── pr-lookup.sh ──────────────────────────────────────────────────────────

@test "wf-ship calls pr-lookup once, alone in its block" {
  assert_sole_call "$SKILL" 'bash ~/.agents/skills/wf-ship/scripts/pr-lookup.sh'
}

@test "pr-lookup prints a hit's URL, draft state and first line, without control bytes" {
  pr_payload "$(jq -cn --arg body "$(printf 'Issue: \033[31mZZZ-0\033[0m\r\nmore')" '{url: "https://github.com/o/r/pull/7", isDraft: false, body: $body}')"

  run bash "$LOOKUP"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'pr_url=https://github.com/o/r/pull/7\npr_draft=no\npr_first_line<<<\nIssue: [31mZZZ-0[0m')" ]
}

@test "pr-lookup keeps an empty first line as a line" {
  pr_payload '{"url":"https://github.com/o/r/pull/7","isDraft":true,"body":null}'
  local out
  out="$(bash "$LOOKUP"; echo .)"
  [ "$out" = "$(printf 'pr_url=https://github.com/o/r/pull/7\npr_draft=yes\npr_first_line<<<\n\n.')" ]
}

@test "pr-lookup prints pr=none and gh's filtered stderr when gh fails" {
  run bash "$LOOKUP"
  [ "$status" -eq 0 ]
  [ "$output" = "$(printf 'pr=none\ngh_log<<<\nno pull requests found for branch [31mfeat')" ]
}

@test "pr-lookup refuses any argument" {
  run bash "$LOOKUP" ready
  [ "$status" -eq 2 ]
  [ ! -e "$STUB_BIN/calls" ]
}

# ─── portability ───────────────────────────────────────────────────────────

# Before-hooks for assert_script_portable, each resetting the world the
# previous shell's run pushed into.
feature_world() { fresh_world; git checkout --quiet -b feat; commit_file a.txt a; }
move_world() { fresh_world; commit_file m.txt m; }

@test "feature mode answers identically under /bin/bash and PATH's bash" {
  assert_script_portable feature_world "$PUSH" --default main
  [ "$(key_values push_exit)" = "0" ] || fail "unexpected output: $output"
  [ "$(section pushed)" = "a.txt" ] || fail "unexpected output: $output"
}

@test "move mode answers identically under /bin/bash and PATH's bash" {
  assert_script_portable move_world "$PUSH" --default main --move-to moved
  [ "$(key_values cherry_pick_exit)" = "0" ] || fail "unexpected output: $output"
  [ "$(section pushed)" = "m.txt" ] || fail "unexpected output: $output"
}

@test "pr-lookup answers identically under /bin/bash and PATH's bash" {
  pr_payload '{"url":"https://github.com/o/r/pull/7","isDraft":true,"body":"Issue: ZZZ-0"}'
  assert_script_portable : "$LOOKUP"
  [ "$(key_values pr_url)" = "https://github.com/o/r/pull/7" ] || fail "unexpected output: $output"
  [ "$(section pr_first_line)" = "Issue: ZZZ-0" ] || fail "unexpected output: $output"
}
