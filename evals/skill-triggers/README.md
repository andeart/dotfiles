# Skill trigger evals

Measures whether a phrase reaches the skill that claims it. `file-work-item` and
`refine-work-item` share most of their vocabulary - issue, bug, ticket, task - so the cases
that matter are the pairs where the same noun has opposite answers, plus the other skills in
this repo that also say "work item".

## Running

```sh
./evals/skill-triggers/run-triggers.sh                    # all cases, 5 runs each
./evals/skill-triggers/run-triggers.sh --case 'refine-*'  # one group
./evals/skill-triggers/run-triggers.sh --runs 1 --jobs 1  # cheap smoke check
```

Each probe is a real API call, so a full run costs real tokens and takes minutes. Results land
under `$TMPDIR` unless `--out-dir` says otherwise; `raw.tsv` holds one row per probe.

Skills load from `agents/` in the working tree, not from `~/.agents`, so a run grades what is
checked out rather than what was last deployed. Probes get the Skill tool and nothing else, and
`--strict-mcp-config` leaves no MCP server reachable, so a probe that correctly triggers
`file-work-item` still cannot create anything in a tracker.

## Why this is not a bats suite

`bats tests/` runs in pre-commit. These cases call the API, cost money, take minutes, and are
stochastic - `--runs` exists because a single probe proves nothing about a trigger boundary.
Run this when a skill description changes, not on every commit.

## Adding a case

One tab-separated line in `cases.tsv`: id, expected skill, prompt. Give the id a prefix that
groups it with its siblings so `--case` can select the group.

`claude plugin eval` is the better long-term home for this - it has `tool_used: Skill` graders,
ablation arms, and an HTML report. It is early-access gated and returned "`plugin eval` is
currently in early access" on this account as of 2026-08-23, which is why this runner exists.
`cases.tsv` maps to its prompt-plus-expected shape if that changes.
