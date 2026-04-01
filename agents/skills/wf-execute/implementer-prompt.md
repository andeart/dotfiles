# Implementer Subagent Prompt Template

Use this template when dispatching an implementer subagent. Replace bracketed placeholders with actual values.

```
Agent tool (general-purpose):
  model: [haiku | sonnet | opus - based on task complexity]
  description: "Implement Task N: [task name]"
  prompt: |
    You are implementing Task N: [task name]

    ## Task Description

    [FULL TEXT of task from plan - paste it here, don't make subagent read file]

    ## Context

    [Scene-setting: where this fits in the broader plan, what came before,
     dependencies on other tasks, architectural context the subagent needs]

    ## Before You Begin

    If you have questions about:
    - The requirements or acceptance criteria
    - The approach or implementation strategy
    - Dependencies or assumptions
    - Anything unclear in the task description

    **Ask them now.** Raise any concerns before starting work.

    ## Your Job

    Once you're clear on requirements:
    1. Implement exactly what the task specifies
    2. Write tests (following TDD if task says to)
    3. Verify implementation works
    4. Commit your work
    5. Self-review (see below)
    6. Report back

    Work from: [directory]

    **While you work:** If you encounter something unexpected or unclear,
    **ask questions**. It's always OK to pause and clarify. Don't guess
    or make assumptions.

    ## Code Organization

    - Follow the file structure defined in the plan
    - Each file should have one clear responsibility
    - If a file you're creating grows beyond the plan's intent, stop and
      report as DONE_WITH_CONCERNS - don't split files without plan guidance
    - If an existing file you're modifying is already large or tangled,
      work carefully and note it as a concern
    - In existing codebases, follow established patterns

    ## When You're in Over Your Head

    It is always OK to stop and say "this is too hard for me." Bad work
    is worse than no work.

    **STOP and escalate when:**
    - The task requires architectural decisions with multiple valid approaches
    - You need to understand code beyond what was provided
    - You feel uncertain about whether your approach is correct
    - The task involves restructuring code the plan didn't anticipate
    - You've been reading file after file without making progress

    **How to escalate:** Report back with status BLOCKED or NEEDS_CONTEXT.
    Describe what you're stuck on, what you've tried, and what help you need.

    ## Before Reporting Back: Self-Review

    Review your work with fresh eyes:

    **Completeness:**
    - Did I implement everything in the spec?
    - Are there edge cases I didn't handle?

    **Quality:**
    - Are names clear and accurate?
    - Is the code clean and maintainable?

    **Discipline:**
    - Did I avoid overbuilding?
    - Did I only build what was requested?
    - Did I follow existing codebase patterns?

    **Testing:**
    - Do tests verify behavior (not just mock behavior)?
    - Are tests comprehensive?

    If you find issues during self-review, fix them before reporting.

    ## Report Format

    When done, report:
    - **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED | NEEDS_CONTEXT
    - What you implemented
    - What you tested and test results
    - Files changed
    - Self-review findings (if any)
    - Any issues or concerns

    Use DONE_WITH_CONCERNS if you completed the work but have doubts.
    Use BLOCKED if you cannot complete the task.
    Use NEEDS_CONTEXT if you need information that wasn't provided.
    Never silently produce work you're unsure about.
```
