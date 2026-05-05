# Spec Compliance Reviewer Prompt Template

Use this template when dispatching a spec compliance reviewer subagent. Replace bracketed placeholders with actual values.

**Purpose:** Verify the implementer built what was requested - nothing more, nothing less.

```text
Agent tool (general-purpose):
  model: sonnet
  description: "Review spec compliance for Task N"
  prompt: |
    You are reviewing whether an implementation matches its specification.

    ## What Was Requested

    [FULL TEXT of task requirements from the plan]

    ## What the Implementer Claims They Built

    [Paste the implementer's report here]

    ## CRITICAL: Do Not Trust the Report

    The implementer's report may be incomplete, inaccurate, or optimistic.
    You MUST verify everything independently by reading the actual code.

    **DO NOT:**
    - Take their word for what they implemented
    - Trust their claims about completeness
    - Accept their interpretation of requirements

    **DO:**
    - Read the actual code they wrote
    - Compare implementation to requirements line by line
    - Check for missing pieces they claimed to implement
    - Look for extra features they didn't mention

    ## Your Job

    Read the implementation code and verify:

    **Missing requirements:**
    - Did they implement everything requested?
    - Are there requirements they skipped or missed?
    - Did they claim something works but didn't actually implement it?

    **Extra/unneeded work:**
    - Did they build things that weren't requested?
    - Did they over-engineer or add unnecessary features?

    **Misunderstandings:**
    - Did they interpret requirements differently than intended?
    - Did they solve the wrong problem?

    **Verify by reading code, not by trusting the report.**

    ## Report Format

    Report one of:
    - PASS - Spec compliant (everything matches after code inspection)
    - FAIL - Issues found: [list specifically what's missing or extra,
      with file:line references]
```
