---
name: wf-config
description: Write or complete a repo's .wf.yml, the settings file the wf-* skill family reads. Use this skill whenever the user says "/wf-config", "set up .wf.yml", "this repo has no .wf.yml", "which wf keys is this repo missing", "configure the wf skills", or any variation of wanting the wf settings written, completed, or checked. Also trigger when a wf-* skill halts saying a key is unset. Do NOT trigger for .workitems.<tracker>.yml, which is file-work-item's; for a legacy .plane.yml, .linear.yml or .jira.yml, which is migrate-work-item-config's; or for harness settings under settings.json, which is update-config's.
---

# Configure `.wf.yml`

Write the settings the `wf-*` family reads, or fill in the keys an existing file leaves out. Every key is required, so a file short of one halts the skill that reads it.

## Output

Happy-path steps produce no progress output. The file, the keys most worth revising, and the sign-off question are what the user sees.

Every stop condition reports in full.

## Step 0: Resolve the repo and the file

```bash
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || { echo 'repo=no'; exit 0; }
echo 'repo=yes'
root=$(git rev-parse --show-toplevel)
echo "root=$root"
[ -f "$root/.wf.yml" ] && echo 'wfconfig_file=yes' || echo 'wfconfig_file=no'
[ -f "$root/.wf.yml" ] || echo "wfconfig_path=$(bash \
  ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh \
  --repo-root "$root" --print-config-path 2>/dev/null)"
[ -f ~/.agents/skills/wf-conventions/wf.yml.template ] \
  && echo 'template=yes' || echo 'template=no'
echo 'workitems<<<'
find "$root" -maxdepth 1 -name '.workitems.*.yml'
```

`find` with a quoted pattern rather than a shell glob: under zsh an unmatched glob is a shell-level error that `2>/dev/null` on the command does not catch, so `ls "$root"/.workitems.*.yml` prints "no matches found" into the block's output right where the marker says a filename would be.

- `repo=no` - stop and tell the user this is not a git repository.
- `template=no` - **stop.** Say the shipped template is not on disk at `~/.agents/skills/wf-conventions/wf.yml.template`, and that `dotfiles push` puts it there. Never write the nine keys from memory: the template is the only place the shipped values live, and a skill that can reconstruct them is the guessing this contract exists to delete.
- `wfconfig_path=` - only printed when the root has no file of its own. A non-empty value means this worktree inherits its settings from that path; Step 1 branches on it. An empty value means nothing resolved anywhere.

Everything below acts on `$root/.wf.yml`, never on a path relative to the working directory. The resolver takes `--repo-root` for the same reason: a scaffolder that writes to the working directory drops a `.wf.yml` wherever the user happened to be standing.

**Every block below opens by re-deriving `root`.** Shell state does not survive from one block to the next, so a `root` assigned here is empty in the next one - and an empty `$root` does not fail loudly, it points the resolver at `--repo-root ""` (exit 2, which reads as a broken config) and both writes below at `/.wf.yml`, the filesystem root. The five skills that read this config bind `root` once at the top of their own Step 0 block for the same reason.

## Step 1: Choose the path

**`wfconfig_file=no` with a non-empty `wfconfig_path=`** - this root is a linked worktree inheriting its settings from the base clone. Report the path, say that changing those settings means running `/wf-config` in that directory, and **stop**. Write nothing here: a worktree-local file would shadow the one the base clone carries, which is the failure the fallback exists to remove.

Do not resolve the file that report names. `/wf-config` run in the base clone validates it there, on the arm that can also fix it.

**`wfconfig_file=no` with an absent or empty `wfconfig_path=`** - go to "Writing a new file". Nothing is inherited, so there is nothing to shadow.

**`wfconfig_file=yes`** - resolve it first, and branch on the exit code:

```bash
root=$(git rev-parse --show-toplevel)
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$root"
rc=$?
echo "resolver_exit=$rc"
[ "$rc" -eq 0 ] && yq 'tag' "$root/.wf.yml"
```

`rc` is captured before anything else runs, and the `tag` call is guarded by it: a rejected config writes nothing below, so its shape is read only to be discarded, and on a malformed file an unguarded `yq` prints a second error the user then has to reconcile with the resolver's.

No `--require` on this call, unlike the five skills that consume the config. They name their keys so an undeclared one halts them at exit 4; here an undeclared key is the input, and halting on it would stop the skill that exists to fill it.

**`resolver_exit=2` or `3`** - print the resolver's stderr, ask the user to fix the file, and write nothing. A rejection emits no dump at all, so there are no keys to read as unset, and reading that silence as "everything is missing" answers the wrong question: the file is not short of keys, it has something wrong in it, and filling keys will not fix what the resolver just named. There is nothing for the merge to merge into either.

**`resolver_exit=0`** - the `yq 'tag'` line picks the path:

| `yq 'tag'` | What reaches it | Path |
| --- | --- | --- |
| `!!map`, non-empty | a real config, complete or short | "Filling an existing file" |
| `!!map`, empty (`{}`) | a root-level `{}` | "Writing a new file" |
| `!!null` | zero-byte, or comments only | "Writing a new file" |
| `!!str` | a root-level scalar | stop |
| more than one line | a multi-document file | stop |

The dump cannot pick between these: an empty file, a comments-only one and `review: {}` all resolve at exit 0 with every key `<unset>`, exactly as an absent file does. The document's own shape is what separates them, and one `yq 'tag'` fork answers it.

A `!!null` file has nothing for the merge to fill - `select(fi==1)` selects nothing and the expression emits zero bytes at exit 0, so the fill would report nine keys written and leave an empty file behind. A root-level `{}` does merge, but into flow style, so it takes the copy path rather than handing back a one-line file.

`!!str` **stops.** A bare scalar reaches exit 0 with every key `<unset>`, so it arrives looking like an ordinary incomplete file, and the merge below would fail with `cannot multiply !!map with !!str`. Say the file's whole content is a scalar rather than a mapping, and ask the user to fix or delete it.

**More than one line** means more than one document, and it **stops.** It reaches here because the resolver rejects a multi-document file only when a key repeats across the documents. The merge would make it worse rather than fixing it: `select(fi==1)` emits both mappings with no `---` between them, which re-reads as one document with duplicate keys, and there the template's value wins over the user's. Say the file holds more than one YAML document and ask the user to collapse it to one.

A root-level list never reaches this table - the resolver rejects it at exit 3.

Every row above is a claim about how `yq` behaves, pinned by `tests/wf-config-scaffolder.bats`. A failure there means this table needs rewriting.

## Writing a new file

Say the repo configures none of the nine keys, offer to write the template, and **ask first**. Never write without an explicit yes.

On yes:

```bash
root=$(git rev-parse --show-toplevel)
cp ~/.agents/skills/wf-conventions/wf.yml.template "$root/.wf.yml"
```

No mode is set here, deliberately: a file that did not exist has none to preserve, so the user's umask decides it the way it decides every other file they create. The fill path below is the one that has a mode to keep.

Then go to "Sign-off".

## Filling an existing file

Collect the keys that came back `<unset>` from Step 1's dump.

**Nothing unset** - say so in one line and stop. There is nothing to write.

Otherwise name them, offer to fill them from the template, and **ask first**.

On yes, merge with the template underneath - never append:

```bash
root=$(git rev-parse --show-toplevel)
tmp=$(mktemp) \
  && cp -p "$root/.wf.yml" "$tmp" \
  && yq ea 'select(fi==0) * select(fi==1)' \
       ~/.agents/skills/wf-conventions/wf.yml.template "$root/.wf.yml" > "$tmp" \
  && mv "$tmp" "$root/.wf.yml"
```

A duplicate YAML key is not an error yq reports - a second `states:` block wins over the first - so appending a `states:` header to a file that already declares `states.shaping` would silently replace a value the user chose, the one thing this path exists to promise it will not do. The merge makes that unrepresentable rather than merely avoided: every key the file declares wins, and only the keys it lacks come from the template.

**`mktemp` and `mv`, never a redirect and never `-i`.** Both shorthands destroy something, silently, at exit 0. `yq ea ... > .wf.yml` truncates the file before yq opens it. `yq ea -i` writes the *first* file, so it leaves `.wf.yml` untouched and overwrites the shipped template instead - which `dotfiles freeze`'s pre-commit hook then harvests, making one repo's config everyone else's template.

**The `cp -p` is there for the mode, not the content.** `mktemp` creates at `600` and `mv` carries that mode onto `.wf.yml`, so without it a fill quietly narrows a `644` config to owner-only - and git tracks no mode but the exec bit, so nothing in a diff or a `git status` would ever show it. Seeding the temp file from the one being filled preserves whatever mode the user chose, and preserves it in both directions: a hard-coded `644` would just as silently widen a config someone deliberately set to `600`. The redirect overwrites the copied content immediately, so only the mode survives the copy. A failed run leaves the temp file behind, which is deliberate: an `rm` on the failure arm would trip this repo's own deletion hook when the skill ran.

Three consequences worth stating rather than discovering: the result is written in the template's key order, it replaces the file rather than appending to it, and yq reflows what it rewrites - comments survive and land with their keys, but blank lines between sections do not, and the template's header comment is prepended to the file. So the promise is not "never overwrite" but **the user's declared values always win**. A shorter list in the file replaces the template's outright rather than merging by index, which is the same rule the resolver applies.

Then re-resolve, and show the dump beside the file so the sign-off is given against what the skills will actually read:

```bash
root=$(git rev-parse --show-toplevel)
bash ~/.agents/skills/wf-conventions/scripts/resolve-wf-config.sh --repo-root "$root"
```

**A key still `<unset>` in that dump means the fill did not fill it, and nothing errored.** The merge gives every key the file declares its own value, and `{}` is a declared value: a leaf written `shaping: {}` or `reviewers: {}` beats the template, survives the merge at exit 0, and resolves `<unset>` exactly as it went in. An empty *section* - `review: {}` - is not this case, since the template's keys merge into it normally. Name each key still unset, say the file declares it as an empty map, and ask the user to remove those keys before re-running. Do not report the fill as done: the user reached this skill from one that halted on such a key, and calling it filled sends them back to the same halt. `tests/wf-config-scaffolder.bats` pins both directions.

## Sign-off

Both paths end here. Show the file, name the keys most likely to need changing for this repo, and **ask the user to confirm they have reviewed and revised it** before concluding:

- `states.*` - matched by name against the project's actual Plane states. A name no state carries resolves to a write that is skipped every time.
- `verify.commands` - what `/wf-ship` and both review skills run. The template ships `[]`; anything added here is executed verbatim from a checked-in file on every ship and once per review cycle.
- `workspace.impl` - `base` or `worktree`, per how work happens in this repo.

The gate is what keeps a complete written file from becoming a value nobody chose. The scaffolder supplies the shape; the user signs off on the content.

## Then

If Step 0's `workitems<<<` marker was followed by nothing, add one line: this repo has no work item tracker config either, and `/file-work-item` writes that one. Write nothing toward it - it needs the tracker resolved through `resolve-tracker.sh` and its exit-10 ask, a root-versus-`tmp/` choice driven by repo visibility, and possibly a gated `.gitignore` change. None of that transfers, and duplicating the flow would create a second opinion about which tracker a repo uses.
