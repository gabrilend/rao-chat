# 208 — Leaving a room

**Phase:** 2 — Server-to-server delivery
**Blocked by:** 204, 207
**Blocks:** 210

## Current Behavior

Nothing exists.  Phase 1's 103 offers the only removal, `confirm_leave`
(removes the pair from the entry, keeps any withheld line, deletes any
flag line), for this issue to call after the call-back.

## Intended Behavior

Owner: "the moment we know that the person has left the room. We should add
messages that do so."  And: "the address will send to everyone and say
"hello I'm not in this room anymore" and if they receive more messages from
them, they get re-added of course because that's how it works in general
right?"

- **Leaving sends a `leave` record** (with a claim id, 204) to every pair on
  the room's send list.
- **A receiver confirms it** by asking the leaving pair "did you make claim
  C?" (204) before removing it (103's `confirm_leave`).  A forged leave is
  not confirmed and changes nothing.
- **A confirmed leave is remembered**: a line in the room's `left` file —
  address (text), port (integer), when confirmed (integer seconds), claim id
  (32 hex).  A members list (207) naming a remembered pair does not re-add
  it.
- **Speaking again re-adds** the pair, as any genuine message does, and
  clears its `left` line — the leaver's own new message or hello is the only
  thing that undoes a leave.
- **What was not yet delivered** to the leaving pair is dropped: its line
  in the room's `delivered` file (202) is removed.

## Rubric

- **A leave notice is a claim, proved in the direction in doubt** (addresses
  R8): only the leaving pair itself can say yes.
- **Every effect of a frame is safe if the frame is replayed later, by
  anyone who recorded it** (structure R13): a replayed old `members` list
  must not undo a confirmed leave.  A replayed `leave` is harder: its
  claim really was made, so the call-back answers yes even after the
  leaver has come back (open question 1).
- **"Delivered" state moves item by item** (structure R21): dropping the
  leaver's pending messages is one line, not a rewrite of every message.

## Where we differ

rmail has no leaving; a contact is removed by editing a file.  The
formation here is **the tombstone**: a confirmed leave leaves a small
record behind, and only the leaver's own newer speech removes it.

- **Gains:** replayed lists are harmless without calling back a pair
  already known to have left; the person can see who left and when.
- **Costs:** one more file per room; ordering "newer than the leave" relies
  on the written time the leaver's server stamps, which a malicious member
  could set — acceptable under the threat model (betrayal by a member is
  outside it).

## Referees

1. **A genuine leave removes.**  A leaves; B calls back, A says yes, B
   removes A and writes `left`.
2. **A forged leave does not.**  C sends a leave naming A's pair: A says
   no; nothing changes.  *Broken:* removing on receipt.
3. **Speaking again re-adds.**  A writes a new message after leaving: B
   files it, adds A back, clears `left`.
4. **A replayed list does not re-add.**  Record a list holding A before the
   leave; replay it after: A stays out.  *Broken:* a leave with no record.
5. **Pending is dropped.**  Messages undelivered to A at the leave are not
   sent afterwards.

## Suggested Implementation Steps

1. The `leave` record and sending it; the claim written (204).
2. Receiving: call back, then `confirm_leave`, then the `left` line and the
   `delivered` line removed.
3. The `left` check in 207's receiving path; clearing it on new speech.
4. The referees above.

## Blockers that are not the owner's

- Needs 204 (confirming), 207 (lists to guard), 202 (`delivered`).

## Open questions

1. **A replayed leave after the leaver returned**: a recorded old `leave`,
   replayed, is answered `yes` (the claim was really made).  Proposed: a
   leave older than the pair's latest filed message is ignored.  Confirm.
2. **Leaving a parent**: phase 1 flags the leaver in its children (nothing
   removes them).  Should leaving a parent offer to leave its children too?

## Related documents

- `notes/vision-planning.md` section 3 ("Leaving"); section 14 ("Answers"
  3, 9; "Follow-up" 2)
- `notes/rmail-rubric/structure-and-defences.md` (R13, open question 7)
