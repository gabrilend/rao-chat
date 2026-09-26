# 207 — Contact syncing within a room

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 205
**Blocks:** 208, 209, 210

## Current Behavior

Nothing exists.

## Intended Behavior

Owner: "could just, have everyone sync their contacts list whenever they
notice that a new person joined the room. We can't tell when someone left.
Also, we should be able to request that others automatically send their
contacts list to us, in the same way that the RGPL requires people to send
their source-code if requested. Like, if we make a special type of message
and put it in the outbox. In the UI it'll probably be tapping a button or
something, or the user could make it auto-triggered..."

- **When a new member is noticed** in a room, this server sends its members
  for that room to every member (a `members` message).
- **Anyone may ask** for a room's members with a `members-ask` message; the
  answer is sent automatically.  In the app, a button, or automatic.
- **Received members are added** (103), except addresses on the ignore
  list (103a) and, in a child room, addresses not in the parent (102).
- **Consent**: being in a room is consent to your address being passed to
  its members.

## Suggested Implementation Steps

1. `members` and `members-ask` inner kinds.
2. Sending on a new member; answering an ask.
3. Adding what arrives, through the ignore filter.
4. Tests: three homes; a newcomer who joined through one reaches all; an
   ignored address sent back is refused; a child room's list never adds an
   outsider of the parent.

## Blockers that are not the owner's

- Needs 205 (joining), 102, 103 and 103a.

## Open questions

1. **Automatic asking.**  How often, if the person turns it on?

## Related documents

- `notes/vision-planning.md` section 3 ("Members spread"); section 14
  ("Answers" 5)
