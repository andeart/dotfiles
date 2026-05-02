# Plane Work Item Writing Conventions

Shared writing rules for Anurag's Plane work items. Both the `plane-create-work-item` and
`plane-refine-work-item` skills Read this file before composing or editing work item content, so
every work item has a consistent voice and shape regardless of whether it's being created from
scratch or refined in place.

See the [Examples](#examples) section at the bottom for a worked example with all three sections.

## Description format

Plane stores work item descriptions as HTML in the `description_html` field. The Plane MCP tools
(`create_work_item`, `update_work_item`) accept HTML directly and Plane's Tiptap-based editor
normalizes it on save: it adds its own Tailwind classes (`editor-paragraph-block`, `list-disc
pl-7 space-y-(--list-spacing-y) tight`, etc.) and a fresh `data-id` to every block. Send the
minimal markup below and let Plane normalize.

Verified markup (round-tripped through `retrieve_work_item_by_identifier`):

- `<p>...</p>` for paragraphs.
- `<h1>...</h1>` through `<h6>...</h6>` for headings. Plane preserves the heading level and adds
  its own `class="editor-heading-block"` and `data-id`. Use `<h3>` for the Impact / Notes /
  Acceptance criteria section headers.
- `<ul><li>...</li></ul>` for bullet lists. Plane wraps the `<li>` text in its own `<p>` block on
  save - you don't need to do this yourself.
- Nested bullets: a `<ul>` directly inside an `<li>`.
- For acceptance criteria checkboxes, use Plane's Tiptap task-list markup:

  ```html
  <ul data-type="taskList">
    <li data-type="taskItem" data-checked="false">A notification is sent when …</li>
    <li data-type="taskItem" data-checked="true">The behavior is tested with …</li>
  </ul>
  ```

  The `data-type="taskList"` / `data-type="taskItem"` attributes are what Plane keys off to
  render real interactive checkboxes (with the `<label><input type="checkbox">` markup). Without
  `data-type`, Plane treats the markup as a plain bullet list.
- For horizontal rules between sections, use Plane's nested-div markup:

  ```html
  <div data-type="horizontalRule"><div></div></div>
  ```

  The `data-type="horizontalRule"` attribute is the signal Plane keys off; the inner empty
  `<div>` is required. Plane fills in its own Tailwind classes (`py-4 border-strong-1`) on save.
  A plain `<hr>` is untested - it may or may not get normalized to this form, so prefer the
  verified div markup.
- `<strong>...</strong>` for bold, `<u>...</u>` for underline, `<em>...</em>` for italic.
- `<a href="…">…</a>` for external links.
- Reference other work items by identifier inline (e.g. `DX-22`). Plane's editor turns these
  into work-item mention chips on render.

When a tool call accepts both `description_html` and `description_stripped`, also pass
`description_stripped` with the plain-text version (no tags, single newlines between blocks).
Plane uses it for search and previews.

## Work Item Description Structure

Every work item description uses up to three sections in this fixed order. Sections are separated
by horizontal rules (`<div data-type="horizontalRule"><div></div></div>`). Use `<h3>` for
section headers.

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
- References to other work items should use Plane's identifier syntax (e.g. `DX-22`).

### 3. Acceptance criteria (required)

A task list (`<ul data-type="taskList">` / `<li data-type="taskItem" data-checked="false">`) of
specific, testable conditions that must be true for the work item to be considered done. Written
in declarative present tense. Never use plain bullet lists for acceptance criteria - always use
the task-list markup so Plane renders them as interactive checkboxes.

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

## Title Conventions

- Concise, action-oriented.
- Starts with a verb or noun phrase describing the deliverable.
- Bug titles must start with "Fix " (e.g. "Fix stale data in dashboard card after refreshing").
- Use sentence case.
- Examples: "Alert when the oven runs continuously for over 1 hour", "Set up Ollama on Windows
  laptop for local AI commands", "Fix away-mode automation not triggering when Wi-Fi presence
  times out".

## Examples

A complete work item with all three sections. If there are no Notes, omit that section and its
surrounding horizontal-rule dividers entirely.

```html
<h3>Impact</h3>
<ul>
  <li>This will automatically secure and conserve the home when nobody is present so we can walk
      out without thinking about locking doors, turning off lights, or adjusting the thermostat.</li>
</ul>

<div data-type="horizontalRule"><div></div></div>

<h3>Notes</h3>
<ul>
  <li>Presence detection should use Wi-Fi presence as the primary method for the first version.</li>
  <li>A door-lock failure is a meaningful edge case that should surface as an alert rather than
      fail silently.</li>
  <li>Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on
      departure.</li>
</ul>

<div data-type="horizontalRule"><div></div></div>

<h3>Acceptance criteria</h3>
<ul data-type="taskList">
  <li data-type="taskItem" data-checked="false">Wi-Fi presence detection is set up for all
      tracked occupants.</li>
  <li data-type="taskItem" data-checked="false">An automation triggers when all tracked
      occupants are detected as away.</li>
  <li data-type="taskItem" data-checked="false">The automation locks all doors.</li>
  <li data-type="taskItem" data-checked="false">An alert is sent if a door lock fails to lock.</li>
  <li data-type="taskItem" data-checked="false">The behavior is tested with a simulated all-away
      state before relying on real presence detection.</li>
</ul>
```

The matching `description_stripped` for the example above. Section headers appear on their own
line; horizontal rules are dropped entirely (Plane omits them from the stripped form):

```text
Impact
- This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.
Notes
- Presence detection should use Wi-Fi presence as the primary method for the first version.
- A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
- Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.
Acceptance criteria
- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
