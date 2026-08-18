---
name: gh-dependabot-config
description: >
  Bootstrap a repository's .github/dependabot.yml with one entry per package
  ecosystem that actually has a manifest checked in, then deliver it as a pull
  request. Use this skill whenever the user says "/gh-dependabot-config", "set
  up Dependabot", "add dependabot.yml", "turn on dependency updates", "get
  dependency PRs for this repo", or any variation of wanting a repo to start
  receiving version-update pull requests. Also trigger when a repo is being
  bootstrapped and Dependabot version updates have not been configured yet, even
  if the user does not name Dependabot. Do NOT trigger for Dependabot alerts or
  security updates - those are repo API toggles owned by `gh-set-default-settings`.
---

# Bootstrap a Dependabot Config

Generate a `.github/dependabot.yml` for the repo you are working in, with an
`updates:` entry only for ecosystems whose manifests are really present, and open
a PR with it.

`package-ecosystem` has no wildcard value. Declaring an ecosystem with no
matching manifest fails the update job with `dependency_file_not_found`, which is
why every entry has to be earned by a file in the tree.

## Division of labour

The generator script owns the deterministic part: the manifest-to-ecosystem
table, the vendored and fixture skips, and the lockfile-based tie-breaks
(`pyproject.toml` to `pip` or `uv`, `package.json` to `npm`, `bun`, or `deno`).

You own the parts a frozen table cannot settle: the drift check in step 1, any
manifest the table does not recognise, and the Terraform/OpenTofu call. Treat the
table as a fast path, never as the authoritative list of what exists.

## Step 0: Locate the script

The script ships beside this file:

```bash
ls ~/.claude/skills/gh-dependabot-config/scripts/generate-dependabot-config.sh \
   ~/.agents/skills/gh-dependabot-config/scripts/generate-dependabot-config.sh 2>/dev/null
```

Use whichever path exists and call it with `bash <path>`, not by executing it
directly - the sync that materialises these files does not guarantee the
executable bit survives. Call this path `<GEN>`.

## Step 1: Self-heal the ecosystem table

Do this on every run, before generating anything. GitHub adds ecosystems over
time (`uv`, `pre-commit`, `rust-toolchain`, and `dotnet-sdk` are all recent), and
a stale table under-detects silently: the config still parses, so nothing ever
surfaces the gap on its own.

1. Ask the script what it knows:

   ```bash
   bash <GEN> --list-ecosystems
   ```

2. Fetch the live list from the options reference and extract every documented
   `package-ecosystem` value:

   <https://docs.github.com/en/code-security/reference/supply-chain-security/dependabot-options-reference>

3. Diff the two sets.

   - **Live list has values the script does not know** - report them, then offer
     to add each one to `MANIFEST_TABLE` in the script, keyed on the manifest
     filename that ecosystem uses. Confirm the filename against the docs before
     adding it; a wrong key is worse than a missing one, because it renders an
     entry that fails on the first run. Making this edit is a change to the
     dotfiles repo, so hand it to the user as its own change rather than folding
     it into the target repo's PR.
   - **Script knows values the live list does not** - report it and leave the
     table alone. A value disappearing from the docs usually means a rename, and
     dropping it blind would silently stop detecting a real ecosystem.
   - **Sets match** - say so in one line and move on.

If the docs cannot be reached, say so plainly and continue with the existing
table. Do not silently skip this step, and do not guess at what changed.

## Step 2: Preflight

Verify each of these before touching anything, and stop with a clear message on
the first failure:

- You are inside a git repo: `git rev-parse --is-inside-work-tree`
- `gh` is authenticated: `gh auth status`
- An `origin` remote exists: `git remote get-url origin`
- The working tree is clean: `git status --porcelain`

Then check for an existing config:

```bash
ls .github/dependabot.yml
```

**If it already exists, stop.** Report that the repo is already configured, show
which ecosystems the current file covers, and offer to diff it against what the
generator would produce now. Never overwrite it as part of this flow - a config
already in place has usually been tuned by hand, and the generator's fixed
template would quietly discard that.

## Step 3: Resolve the assignee

Assignees must have write access to the repository, and an organization is not a
valid assignee, so the owner cannot be used directly on an org-owned repo.

```bash
gh repo view --json owner,name --jq '.owner.login + " " + (.owner.type // "")'
gh api /repos/{owner}/{repo} --jq '.owner.type'
gh api /user --jq '.login'
```

- `owner.type` is `User` - assign to the owner.
- `owner.type` is `Organization` - assign to the authenticated user from
  `gh api /user`.

Fall back to the authenticated user rather than dropping the `assignees` block,
so the PRs still land on someone. Call the result `<ASSIGNEE>`.

## Step 4: Generate

```bash
bash <GEN> --assignee <ASSIGNEE> > /tmp/dependabot.yml
```

The config goes to stdout; the detection report goes to stderr. Read the report -
it names every ecosystem found, every manifest skipped as vendored or fixture
code, and any decision left to you.

## Step 5: Review the judgment cases

Before writing the file, resolve anything the script flagged or missed:

- **Terraform vs OpenTofu** - `.tf` files match both and no file inspection can
  tell them apart. The script renders `terraform`. Check the repo for OpenTofu
  usage (a `.tofu` file, `tofu` in CI, `.terraform.lock.hcl` alongside OpenTofu
  workflows) and switch the value if that is what it runs.
- **Unrecognised manifests** - scan the tree for dependency-manifest-shaped files
  the report did not account for. If you find one, check it against the live
  ecosystem list from step 1 before concluding the repo has no entry for it.
- **Monorepos** - the script emits `directories:` when an ecosystem spans several
  paths. `directories` accepts globs and `directory` does not, so collapse a long
  list to a glob (`/packages/*`) where that is genuinely equivalent.
- **Skipped paths** - confirm the skips were right. A repo that really does vendor
  a dependency it maintains may want an entry the skip list suppressed.

## Step 6: Deliver as a pull request

The generated config is a commit on the default branch, which the baseline
ruleset does not allow, so this always goes through a PR.

```bash
git checkout -b add-dependabot-config
mkdir -p .github
cp /tmp/dependabot.yml .github/dependabot.yml
git add .github/dependabot.yml
git commit -m "Add a Dependabot version-update config"
git push -u origin add-dependabot-config
gh pr create --fill
```

Never commit this directly to the default branch, even where the ruleset would
allow it.

## Step 7: Report

Close with a short summary:

- Ecosystems detected, and the directory each entry covers
- Manifests skipped, and why
- Any judgment call you made in step 5, stated as a decision the user can reverse
- The drift-check result from step 1
- The PR URL

## The fixed template

Every entry gets the same defaults; only the ecosystem and directory vary.

```yaml
- package-ecosystem: <detected>
  directory: /
  schedule:
    interval: weekly
  cooldown:
    default-days: 30
  assignees:
    - <ASSIGNEE>
```

`cooldown.default-days: 30` lets a release sit in public for a month before it is
proposed. GitHub already applies a 3-day cooldown when none is configured, so this
widens an existing default rather than introducing a new concept. Cooldown applies
to version updates only and never to security updates, so it cannot delay a CVE
fix. The semver-specific cooldown keys are not supported on `github-actions`,
`pre-commit`, or `docker`, so `default-days` is the only knob that works
everywhere and the template stays uniform.
