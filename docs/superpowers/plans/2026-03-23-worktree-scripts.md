# Worktree Scripts Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add two standalone bash scripts - `git-ws-start` and `git-ws-stop` - to `git/bin/` that replace the Claude `/worktree-start` and `/worktree-end` skills.

**Architecture:** Two self-contained bash scripts with no shared library, matching the style of existing scripts in `git/bin/`. No test framework exists for bash in this project; each task includes manual verification steps.

**Tech Stack:** bash, git, gh (GitHub CLI, optional)

---

## File Map

| Action | Path | Purpose |
|--------|------|---------|
| Create | `git/bin/git-ws-start` | Worktree creation script |
| Create | `git/bin/git-ws-stop` | Worktree teardown script |

Note: `README.md` uses a `git/bin/*` wildcard that already covers new files per the dotfiles convention — no update needed.

---

### Task 1: Write `git-ws-start`

**Files:**
- Create: `git/bin/git-ws-start`

- [ ] **Step 1: Write the script**

Create `git/bin/git-ws-start` with the following content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─── word lists ───────────────────────────────────────────────────────────────
adjectives=(
  bold    brave   bright  calm    clean   clear   cool    deep
  dry     fair    fast    firm    flat    free    fresh   full
  great   hard    high    keen    kind    lean    light   long
  neat    new     noble   old     open    pure    quiet   raw
  rich    safe    sharp   slim    smart   soft    still   strong
  swift   thin    true    vast    warm    wide    wild    wise
  young   dark    fine    late
)
nouns=(
  arch    arrow   birch   blade   bluff   brook   cedar   cliff
  cloud   coral   cove    crest   dawn    dune    ember   falcon
  fern    field   flame   forest  gate    glade   grove   harbor
  knoll   lake    maple   marsh   meadow  mesa    oak     pass
  peak    pine    plain   pond    reef    ridge   river   shore
  spark   stone   storm   tide    torch   trail   vale    willow
  shield  frost   mist    north
)
# 36-character set: digits + uppercase letters
charset='0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ'

# ─── argument parsing ──────────────────────────────────────────────────────────
branch_name=""
base_branch=""
custom_dir=""

usage() {
  echo "usage: git ws-start [branch-name] [--base <branch>] [--dir <path>]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      [[ $# -lt 2 ]] && { echo "error: --base requires a value" >&2; usage; exit 1; }
      base_branch="$2"; shift 2 ;;
    --dir)
      [[ $# -lt 2 ]] && { echo "error: --dir requires a value" >&2; usage; exit 1; }
      custom_dir="$2"; shift 2 ;;
    --*)
      echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *)
      [[ -n "$branch_name" ]] && { echo "error: unexpected argument: $1" >&2; usage; exit 1; }
      branch_name="$1"; shift ;;
  esac
done

# ─── git repo check ────────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "error: not inside a git repository." >&2
  exit 1
fi

repo_root="$(git rev-parse --show-toplevel)"

# ─── resolve base branch ──────────────────────────────────────────────────────
if [[ -z "$base_branch" ]]; then
  if git rev-parse --verify main &>/dev/null; then
    base_branch="main"
  elif git rev-parse --verify master &>/dev/null; then
    base_branch="master"
  else
    echo "error: no 'main' or 'master' branch found. Specify one with --base <branch>." >&2
    exit 1
  fi
else
  if ! git rev-parse --verify "$base_branch" &>/dev/null; then
    echo "error: branch '$base_branch' does not exist." >&2
    exit 1
  fi
fi

# ─── resolve branch name ──────────────────────────────────────────────────────
if [[ -z "$branch_name" ]]; then
  adj="${adjectives[$((RANDOM % ${#adjectives[@]}))]}"
  noun="${nouns[$((RANDOM % ${#nouns[@]}))]}"
  c1="${charset:$((RANDOM % 36)):1}"
  c2="${charset:$((RANDOM % 36)):1}"
  branch_name="${adj}-${noun}-${c1}${c2}"

  printf "Generated branch name: %s\nProceed? [y/n] " "$branch_name"
  read -r answer
  case "$answer" in
    y|Y) ;;
    *) echo "Aborted. Re-run to generate a new name."; exit 0 ;;
  esac
fi

# ─── validate branch doesn't exist ────────────────────────────────────────────
if git rev-parse --verify "$branch_name" &>/dev/null; then
  echo "error: branch '$branch_name' already exists." >&2
  exit 1
fi

# ─── resolve worktree path ────────────────────────────────────────────────────
if [[ -n "$custom_dir" ]]; then
  worktree_path="$custom_dir"
else
  repo_parent="$(dirname "$repo_root")"
  repo_name="$(basename "$repo_root")"
  sibling_dir="${repo_parent}/${repo_name}-worktrees"
  worktree_path="${sibling_dir}/${branch_name}"

  if [[ ! -d "$sibling_dir" ]]; then
    printf "Directory '%s' does not exist. Create it? [y/n] " "$sibling_dir"
    read -r answer
    case "$answer" in
      y|Y) ;;
      *) echo "Aborted."; exit 0 ;;
    esac
  fi
fi

# ─── create worktree ──────────────────────────────────────────────────────────
mkdir -p "$(dirname "$worktree_path")"
git worktree add -b "$branch_name" "$worktree_path" "$base_branch"

# ─── success ──────────────────────────────────────────────────────────────────
printf "\nWorktree '%s' is ready. Start working by running:\n\n  cd %s\n\n" \
  "$branch_name" "$worktree_path"
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x git/bin/git-ws-start
```

- [ ] **Step 3: Manually verify — usage error**

```bash
cd git/bin
./git-ws-start --unknown-flag
```

Expected: prints `error: unknown option: --unknown-flag` and the usage line, exits non-zero.

- [ ] **Step 4: Manually verify — random name prompt**

```bash
./git-ws-start
```

Expected: prints `Generated branch name: <adj>-<noun>-XX` and `Proceed? [y/n]`. Type `n` and confirm it prints `Aborted. Re-run to generate a new name.` and exits cleanly.

- [ ] **Step 5: Manually verify — end-to-end creation (dry run in a test repo)**

In any git repo with a `main` branch:

```bash
/path/to/dotfiles/git/bin/git-ws-start test-branch-ZZ
```

Expected: creates the `-worktrees` sibling directory (after y/n prompt), creates a new worktree at `<sibling>-worktrees/test-branch-ZZ`, prints the `cd` path. Clean up with:

```bash
git worktree remove ../<repo>-worktrees/test-branch-ZZ
git branch -d test-branch-ZZ
rmdir ../<repo>-worktrees
```

- [ ] **Step 6: Commit**

```bash
git add git/bin/git-ws-start
git commit -m "Add git-ws-start script"
```

---

### Task 2: Write `git-ws-stop`

**Files:**
- Create: `git/bin/git-ws-stop`

- [ ] **Step 1: Write the script**

Create `git/bin/git-ws-stop` with the following content:

```bash
#!/usr/bin/env bash
set -euo pipefail

# ─── argument parsing ──────────────────────────────────────────────────────────
create_pr=false
branch_name=""

usage() {
  echo "usage: git ws-stop <branch-name> [--pr]" >&2
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pr)
      create_pr=true; shift ;;
    --*)
      echo "error: unknown option: $1" >&2; usage; exit 1 ;;
    *)
      [[ -n "$branch_name" ]] && { echo "error: unexpected argument: $1" >&2; usage; exit 1; }
      branch_name="$1"; shift ;;
  esac
done

if [[ -z "$branch_name" ]]; then
  echo "error: branch name required." >&2; usage; exit 1
fi

# ─── git repo check ────────────────────────────────────────────────────────────
if ! git rev-parse --is-inside-work-tree &>/dev/null; then
  echo "error: not inside a git repository." >&2
  exit 1
fi

# ─── must be run from the main working tree ────────────────────────────────────
# Check if current dir is inside any non-primary worktree.
current_dir="$(pwd -P)"
first_wt=true
while IFS= read -r line; do
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    wt_path="${BASH_REMATCH[1]}"
    wt_path="$(cd "$wt_path" && pwd -P 2>/dev/null || echo "$wt_path")"
    if [[ "$first_wt" == true ]]; then
      first_wt=false
    elif [[ "$current_dir" == "$wt_path" || "$current_dir" == "$wt_path/"* ]]; then
      echo "error: git ws-stop must be run from the main working tree, not from inside a worktree." >&2
      exit 1
    fi
  fi
done < <(git worktree list --porcelain)

# ─── find the worktree for the given branch ────────────────────────────────────
worktree_path=""
current_wt=""
while IFS= read -r line; do
  if [[ "$line" =~ ^worktree\ (.+)$ ]]; then
    current_wt="${BASH_REMATCH[1]}"
  elif [[ "$line" == "branch refs/heads/$branch_name" ]]; then
    worktree_path="$current_wt"
    break
  fi
done < <(git worktree list --porcelain)

if [[ -z "$worktree_path" ]]; then
  echo "error: no worktree found for branch '$branch_name'." >&2
  exit 1
fi

# ─── safety gate: uncommitted changes ─────────────────────────────────────────
dirty="$(git -C "$worktree_path" status --porcelain 2>/dev/null)"
if [[ -n "$dirty" ]]; then
  echo "error: '$branch_name' has uncommitted changes:" >&2
  git -C "$worktree_path" status --short >&2
  printf "\nCommit or stash your work, then re-run.\n" >&2
  exit 1
fi

# ─── safety gate: unpushed commits ────────────────────────────────────────────
if ! unpushed="$(git -C "$worktree_path" log '@{upstream}..' --oneline 2>/dev/null)"; then
  echo "error: '$branch_name' has no upstream set. Push the branch first, then re-run." >&2
  exit 1
fi
if [[ -n "$unpushed" ]]; then
  echo "error: '$branch_name' has unpushed commits:" >&2
  echo "$unpushed" >&2
  printf "\nPush your work, then re-run.\n" >&2
  exit 1
fi

# ─── optional PR creation ─────────────────────────────────────────────────────
pr_url=""
if [[ "$create_pr" == true ]]; then
  if ! command -v gh &>/dev/null; then
    echo "error: 'gh' (GitHub CLI) is not installed. Install it or omit --pr." >&2
    exit 1
  fi
  pr_url="$(gh pr create --head "$branch_name" --fill)"
fi

# ─── remove worktree and branch ───────────────────────────────────────────────
git worktree remove "$worktree_path"

if ! git branch -d "$branch_name" 2>/dev/null; then
  echo "error: could not delete branch '$branch_name' — it may have unmerged changes." >&2
  printf "       To force-delete it: git branch -D %s\n" "$branch_name" >&2
  exit 1
fi

# ─── summary ──────────────────────────────────────────────────────────────────
[[ -n "$pr_url" ]] && echo "PR created: $pr_url"
echo "Worktree '$branch_name' removed. Branch deleted."
```

- [ ] **Step 2: Make it executable**

```bash
chmod +x git/bin/git-ws-stop
```

- [ ] **Step 3: Manually verify — missing branch name**

```bash
./git-ws-stop
```

Expected: prints `error: branch name required.` and usage line, exits non-zero.

- [ ] **Step 4: Manually verify — nonexistent branch**

```bash
./git-ws-stop no-such-branch-xyz
```

Expected: prints `error: no worktree found for branch 'no-such-branch-xyz'.`

- [ ] **Step 5: Manually verify — end-to-end (create then stop)**

Use `git-ws-start` to create a test worktree, push the branch, then run from the main repo root:

```bash
git ws-start test-stop-verify
# (accept generated or provide name; push the empty branch: git -C <path> push -u origin <branch>)
git ws-stop test-stop-verify
```

Expected: prints `Worktree 'test-stop-verify' removed. Branch deleted.`

- [ ] **Step 6: Commit**

```bash
git add git/bin/git-ws-stop
git commit -m "Add git-ws-stop script"
```

