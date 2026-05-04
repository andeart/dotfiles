---
name: wf-wrap
description: Wrap up work after a PR merges - switch back to the default branch, pull, delete the merged feature branch, and mark the corresponding Plane work item as Done. Use this skill whenever the user says "/wf-wrap", "wrap this up", "wrap up the merge", "post-merge cleanup", "switch back to main and clean up", or any variation of wanting to clean up after merging a PR. Do NOT trigger for shipping work for review (use /wf-ship) or for cleaning up older merged branches (use /wf-prune).
---

# Wrap Up After Merge

Run the post-merge cleanup sequence in one shot: switch back to the default branch, pull, mark the associated Plane work item as Done, then delete the just-merged feature branch. Strong precondition checks; no confirmations once they pass.
