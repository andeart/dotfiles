# Work Item Writing Conventions

Shared writing rules for Anurag's work items, whatever tracker a repo files into. The
`file-work-item` and `refine-work-item` skills Read this file before composing or editing any
work item body, so a work item reads the same whether it was created from scratch or refined in
place, and whether it landed in Plane, GitHub, Jira, or GitLab.

**Nothing tracker-specific belongs in this file.** Markup, field names, API and CLI calls,
config keys, and URL shapes live in `references/<tracker>.md`. Only the resolved tracker's are
read - `RESOLUTION.md` covers how that tracker gets picked.

See the [Example](#example) at the bottom for a worked body with all three sections.

## Terminology

"Work item" is the neutral term used throughout this file. Each tracker has its own native noun
- Plane says work item, GitHub and GitLab and Jira say issue - and the reference file names it.
Use the resolved tracker's noun in anything the user reads. When the user says "issue",
"ticket", or "task", treat it as a synonym for whatever the resolved tracker calls it, not as a
signal about which tracker they mean.

## Work item description structure

Every description uses up to three sections in this fixed order, separated by horizontal rules,
with each header at the third heading level. How a rule and a heading are expressed is the
tracker's business; the order and the level are not.

### 1. Impact (required)

A single bullet point that begins with "This will..." and communicates the benefit of delivering
this work item. The tone is outcome-oriented: describe what the user or household gains, not what
the code does.

Rules:

- Exactly one bullet point.
- Always starts with "This will...". For bugs, describe the functional outcome the fix achieves,
  not just that a bug is being fixed.
  - Good: "This will restore reliable presence detection so the away-mode automation triggers consistently"
  - Avoid: "This will fix the presence detection bug"
- Communicates a clear benefit. A "so [reason]" clause is fine but not required as long as the
  benefit is evident.
- Speaks from the perspective of the people affected ("us", "I", "Bry and me"), not the system.

### 2. Notes (optional)

Additional context, links, constraints, or open questions that don't belong in Impact or AC. Each
bullet is a self-contained thought.

Rules:

- Each bullet is one idea. Keep them independent so they can be reordered or removed without
  breaking context.
- Do not echo acceptance criteria with different phrasing. If a point is testable and belongs in
  AC, put it there instead.
- Open questions or decisions that need investigation should be called out explicitly (e.g.
  "**Open question:** ...").
- Reference other work items by their identifier. Every tracker in `references/` renders a bare
  identifier as a link or a mention chip; the reference file says what that identifier looks
  like.

### 3. Acceptance criteria (required)

A checklist of specific, testable conditions that must be true for the work item to be considered
done, written in declarative present tense. Always use the tracker's interactive checkbox markup,
never a plain bullet list - the reference file gives the exact form.

Rules:

- Each item is a **declarative present-tense statement** describing a condition or behavior (e.g.
  "A notification is sent..." not "Send a notification" or "We should send a notification").
- Items should be independently verifiable. Avoid compound criteria joined by "and" unless the
  two parts are truly inseparable.
- Order: core behavior first, then edge cases, then dashboard/notification integration, then
  testing steps last.
- Testing criteria typically appear at the end and start with "The behavior is tested with...".
- Avoid implementation details. Say *what* must be true, not *how* to make it true. Implementation
  guidance belongs in Notes.
- For bugs, describe the corrected behavior, not the broken state.

## Title conventions

- Concise, action-oriented.
- Starts with a verb or noun phrase describing the deliverable.
- Bug titles must start with "Fix " (e.g. "Fix stale data in dashboard card after refreshing").
- Use sentence case.
- Examples: "Alert when the oven runs continuously for over 1 hour", "Set up Ollama on Windows
  laptop for local AI commands", "Fix away-mode automation not triggering when Wi-Fi presence
  times out".

## Estimate

Every work item gets a story-point estimate, assigned by a single global rule that is identical
across every tracker and every project, regardless of how a given project's estimate set is
labelled.

**The scale is Fibonacci:** 1, 2, 3, 5, 8, 13, 21, ...

**The semantic is hours-based:** pick the Fibonacci number equal to, or immediately above, the
number of hours the task is expected to take. Examples: 1h → 1, 3h → 3, 4h → 5, 6h → 8, 9h → 13.
The estimate is a rounded-up effort proxy, not a precise time log.

### Choosing the value

Infer the expected hours from the scope of the work being described, then map to the Fibonacci
point per the rule above. Surface the reasoning in the chat preview so it can be corrected, e.g.:

```text
Estimate: 5 (≈4h)
```

Only ask the user for an hours figure when the description genuinely doesn't give enough to gauge
scope. A user-supplied hours figure or a user-supplied estimate always overrides the inferred one.

### Recording the value

Trackers vary in whether they have an estimate field at all, and in what they want sent for it.
The reference file says how its tracker records the value - and, where the tracker has nowhere to
put it, says that too.

Choosing the estimate is not conditional on the tracker being able to store it. Derive it and show
it in the preview either way: the number is a piece of the thinking, and it is worth seeing even
when it ends up living only in the conversation.

## Previewing to the user before sending

Two distinct surfaces, and they are never the same text:

- **Chat preview (what the user reviews before approval):** human-readable rendered markdown - the
  proposed title on its own line, then `### Impact`, `### Notes`, `### Acceptance criteria`
  headings separated by `---` rules, plain bullets for Impact and Notes, and `- [ ]` items for
  acceptance criteria. This shape is identical on every tracker.
- **Wire format (what the tracker receives):** defined by the resolved tracker's reference file.
  Never paste it into chat. The user is reviewing content, not markup, and on trackers whose wire
  format is HTML the markup buries the words.

Manual mode is the one exception. There the user pastes the body into the tracker themselves, so
the wire format *is* the deliverable and belongs in the reply, fenced.

## Reporting after the write

Once a create or update lands, print this block and nothing else. No prose summary, no restatement
of the description, no list of what changed - the user approved the content at the preview step,
and this only confirms what the tracker now holds.

```text
Issue: [ZZ-123](https://tracker.example/browse/ZZ-123)
Assignee: anuragd
State: Todo
Priority: low
Estimate: 3
Cycle: ship
Module: client
Labels: tech-debt
```

One field per line. `Issue:` is always first and `Assignee:` always second; after those, list the
fields the resolved tracker actually has, in the order its reference file gives them. A field with
no value gets a dash - never an omitted line, and never the word "none":

```text
Cycle: -
```

Compose the block from what this run already holds: the values it sent, or the ones a fetch
returned earlier. Do not re-read the work item to render it. A read-back costs a call and can only
ever disagree with what was just written, which turns a confirmation into a second source of
truth.

`Issue:` links the identifier when the resolved tracker's reference file can build a URL from the
config at hand, and prints the bare identifier when it cannot. Never fill a URL in from a guess: a
link that resolves nowhere is worse than an identifier that was never a link.

Manual mode has nothing to report, because nothing was written. The fields block that mode already
prints is its whole output.

## Example

A complete work item with all three sections, in the chat-preview form described above. If there
are no Notes, omit that section entirely.

Each reference file renders this same body in its own wire format, so the four are directly
comparable. The `---` rules are the preview's spelling of the separators required above; a tracker
whose wire format expresses them differently says so in its own file.

```markdown
Automate away-mode when the house is empty

### Impact

- This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.

---

### Notes

- Presence detection should use Wi-Fi presence as the primary method for the first version.
- A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
- Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.

---

### Acceptance criteria

- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
