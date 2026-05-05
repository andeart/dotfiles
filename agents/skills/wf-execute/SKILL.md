---
name: wf-execute
description: Execute an implementation plan from an MD file using subagent-driven development - dispatches a fresh subagent per task with two-stage review (spec compliance + code quality) after each. Use this skill whenever the user says "/wf-execute", "execute this plan", "run this plan", "implement this plan", or provides a path to a plan file they want executed. Also trigger when the user has just finished writing a plan and wants to start implementation.
---

# Execute Plan

Load a plan from an MD file, review it, then execute every task by dispatching fresh subagents - one per task, with two-stage review after each.

**Announce at start:** "Using execute-plan to implement `<plan-file>`."

## Step 1: Load and Review

1. The user provides a path to the plan file (as an argument or in conversation). Read it.
2. Review critically - identify questions, gaps, or concerns.
3. If concerns exist, raise them with the user before proceeding.
4. If no concerns, extract every task with its full text, context, and acceptance criteria. Create a TodoWrite with all tasks.

## Step 2: Execute Tasks (sequentially)

For each task, run this cycle:

### 2a. Choose a model

Pick the least powerful model that can handle the task:

| Signal | Model |
| ------ | ----- |
| Touches 1-2 files, clear spec, mechanical work | `haiku` |
| Touches multiple files, integration concerns | `sonnet` |
| Architecture decisions, broad codebase understanding, design judgment | `opus` |

When in doubt, go one tier up.

### 2b. Dispatch implementer subagent

Use the Agent tool (`general-purpose` type) with the chosen model. Construct the prompt from `./implementer-prompt.md` - paste the full task text and context directly into the prompt. Never make the subagent read the plan file.

### 2c. Handle implementer status

The implementer reports one of four statuses:

- **DONE** - Proceed to spec review (2d).
- **DONE_WITH_CONCERNS** - Read the concerns. If they're about correctness or scope, address before review. If observational, note them and proceed to spec review.
- **NEEDS_CONTEXT** - Provide the missing context and re-dispatch.
- **BLOCKED** - Assess the blocker:
  1. Context problem - provide more context, re-dispatch same model.
  2. Needs more reasoning - re-dispatch with a more capable model.
  3. Task too large - break into smaller pieces.
  4. Plan itself is wrong - escalate to the user.

Never ignore an escalation or retry the same model without changes.

### 2d. Spec compliance review

Dispatch a reviewer subagent (use `sonnet` model) following `./spec-reviewer-prompt.md`. Provide the full task requirements and the implementer's report.

The spec reviewer reads the actual code and verifies:
- **Missing requirements** - anything skipped or unimplemented
- **Extra work** - features or additions not in spec
- **Misunderstandings** - requirements interpreted incorrectly

If the reviewer finds issues:
1. The implementer subagent fixes them (re-dispatch with fix instructions).
2. The spec reviewer reviews again.
3. Repeat until approved.

Do not proceed to code quality review until spec compliance passes.

### 2e. Code quality review

Dispatch a reviewer subagent (use `sonnet` model, or `opus` for complex tasks) following `./code-quality-reviewer-prompt.md`. Provide the task summary, what was implemented, and the git SHAs (before and after).

The code quality reviewer checks:
- Code cleanliness and maintainability
- Test quality and coverage
- File organization and single-responsibility
- Adherence to existing codebase patterns

If the reviewer finds Critical or Important issues:
1. Dispatch a fix subagent with specific instructions.
2. The code quality reviewer reviews again.
3. Repeat until approved.

Minor issues can be noted but don't block progress.

### 2f. Mark complete

Mark the task as completed in TodoWrite. Move to the next task.

## Step 3: Final Review

After all tasks are complete, dispatch a final code review subagent (`superpowers:code-reviewer` type) covering the entire implementation. This catches cross-task integration issues that per-task reviews miss.

## Step 4: Report Completion

Tell the user:
- All tasks are complete
- Summary of what was built
- Any concerns or observations noted along the way
- The final review result

Let the user decide next steps (commit, PR, further changes, etc.).

## Rules

- Execute tasks sequentially - never dispatch multiple implementers in parallel (they'd conflict).
- Always provide full task text to subagents - never make them read the plan file.
- Include scene-setting context so the subagent understands where the task fits in the larger picture.
- Never skip reviews (spec compliance OR code quality).
- Never proceed with unfixed issues from reviews.
- If a subagent asks questions, answer clearly before letting them proceed.
- If a reviewer finds issues, the fix-then-re-review loop must complete before moving on.
- Stop and ask the user when blocked rather than guessing.
