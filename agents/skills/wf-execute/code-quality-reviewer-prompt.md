# Code Quality Reviewer Prompt Template

Use this template when dispatching a code quality reviewer subagent. Replace bracketed placeholders with actual values.

**Purpose:** Verify the implementation is well-built - clean, tested, maintainable.

**Only dispatch after spec compliance review passes.**

```
Agent tool (superpowers:code-reviewer):
  model: [sonnet for most tasks, opus for complex ones]
  description: "Review code quality for Task N"
  prompt: |
    Review the code changes for this task.

    ## What Was Implemented

    [From implementer's report - summary of what was built]

    ## Requirements

    [Task requirements from the plan]

    ## Changes

    Base SHA: [commit hash before this task started]
    Head SHA: [current commit hash]

    Run `git diff <base>..<head>` to see the changes.

    ## Review Checklist

    **Code quality:**
    - Is the code clean, readable, and maintainable?
    - Are names clear and accurate?
    - Is there unnecessary complexity?
    - Are there any code smells?

    **Testing:**
    - Are tests comprehensive?
    - Do tests verify behavior (not just mock behavior)?
    - Are edge cases covered?

    **File organization:**
    - Does each file have one clear responsibility?
    - Are units decomposed so they can be understood and tested independently?
    - Did this change create new files that are already large, or significantly
      grow existing files? (Don't flag pre-existing file sizes.)

    **Codebase consistency:**
    - Does the implementation follow existing patterns in the codebase?
    - Are there style inconsistencies with surrounding code?

    ## Report Format

    **Strengths:** What's done well.

    **Issues:** Categorize as:
    - Critical - must fix (bugs, security issues, correctness problems)
    - Important - should fix (significant quality concerns)
    - Minor - nice to fix (style nits, small improvements)

    **Assessment:** APPROVED | CHANGES_REQUESTED

    Only request changes for Critical or Important issues.
    Minor issues should be noted but don't block approval.
```
