# Linear Issue Example

A complete issue with all three sections. If there are no Notes, omit that section and its
surrounding `---` dividers entirely.

```markdown
### Impact

* This will automatically secure and conserve the home when nobody is present so we can walk out without thinking about locking doors, turning off lights, or adjusting the thermostat.

---

### Notes

* Presence detection should use Wi-Fi presence as the primary method for the first version.
* A door-lock failure is a meaningful edge case that should surface as an alert rather than fail silently.
* Inspired by a friend's setup that locks doors, turns off lights, and turns down heat on departure.

---

### Acceptance criteria

- [ ] Wi-Fi presence detection is set up for all tracked occupants.
- [ ] An automation triggers when all tracked occupants are detected as away.
- [ ] The automation locks all doors.
- [ ] An alert is sent if a door lock fails to lock.
- [ ] The behavior is tested with a simulated all-away state before relying on real presence detection.
```
