# 208 — Leaving a room

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 204, 207
**Blocks:** 210

## Current Behavior

Nothing exists.  103 offers removing a member by its own leave.

## Intended Behavior

Owner: "the moment we know that the person has left the room. We should add
messages that do so."  And: "the address will send to everyone and say
"hello I'm not in this room anymore" and if they receive more messages from
them, they get re-added of course because that's how it works in general
right?"

- **Leaving sends a `leave` message** to every member.
- **A receiver confirms it** by asking the leaving address "did you leave?"
  (204) before removing it (103).  A forged leave is not confirmed and
  changes nothing.
- **Speaking again re-adds** the address, as any genuine message does.
- **Messages not yet delivered** to the leaving address are dropped once
  the leave is confirmed.

## Suggested Implementation Steps

1. The `leave` inner kind; sending it.
2. Receiving: confirm, then remove; drop its outbox.
3. Tests: a genuine leave removes; a forged one does not; speaking again
   re-adds.

## Blockers that are not the owner's

- Needs 204 (confirming) and 207 (members to tell).

## Related documents

- `notes/vision-planning.md` section 3 ("Leaving"); section 14 ("Answers"
  3, 9; "Follow-up" 2)
