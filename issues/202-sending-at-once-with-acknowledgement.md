# 202 — Sending at once, with acknowledgement and retries

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 201
**Blocks:** 203, 204, 205, 210

## Current Behavior

Nothing exists.  rmail acknowledges each delivery and retries unreachable
contacts with a slowing timer (30 seconds, then longer, up to 2 hours,
never giving up); it can hold a new message until a contact's timer comes
due.

## Intended Behavior

- **A new message goes out immediately** to every address on the room's
  send list (members minus withheld, 103).  The timer governs only retries
  after a failure.
- **A delivery counts only when acknowledged** by the receiving server.
  Until then the message is "not yet delivered" to that address.
- **Retries slow down and never give up**, as rmail's.  Owner: "letting the
  messages pile up with unsent contacts still waiting is fine probably,
  unless it strains the rmail single-threaded messaging core engine in which
  case we'll re-assess at scale."
- **Receiving**: open the frame (201) — the key that opens it says which
  room it is for — and file it there (105), unless the sending address is
  on the ignore list at `hide` (103a's filing choice).  An address that
  fails a child room's parent check is filed and flagged, not refused
  (103).  Holding the token is being invited, so a
  genuine message from a new address is filed; the address becomes a
  member once its hello (205) says where to call back.  Acknowledge, so
  the sender stops retrying.
- **Addresses are added freely**: a second address for a member is tried
  beside the first; the one that answers moves to the front, as in rmail.

## Suggested Implementation Steps

1. Outbox per address; sending on filing.
2. Acknowledgement and the "not yet delivered" state.
3. Retry timer per address.
4. Receiving: open, file (or refuse, as above), acknowledge.
5. Measure the queue at scale (the owner's condition for re-assessing).
6. Tests: two homes on one machine; a delivery while the reader is down
   arrives when it returns; a repeat is `duplicate`; a conflict is an
   error.

## Blockers that are not the owner's

- Needs 201; filing needs 105; the ignore refusal needs 103a; flagging
  needs 102 and 103.

## Open questions

1. **An edit that arrives before its message** (105): hold it until the
   message arrives, or refuse it?
2. **What "strains the engine" means**, as a number to measure against.

## Related documents

- `notes/vision-planning.md` sections 5 ("The one change for chat"), 14
